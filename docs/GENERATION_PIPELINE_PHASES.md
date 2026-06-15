# Generation Pipeline Phases — and Where the American Accent Leaks In

Traces a generation prompt from the SwiftHablare entry point to WAV bytes, then
pinpoints where an American-English accent is introduced. Verified against the
checked-out source and an on-disk Qwen3-TTS model config on 2026-06-15.

## The phases

```
caller (Produciesta / SwiftHablare)
  │  text + voiceId + languageCode (e.g. "en")
  ▼
[1] VoxAltaVoiceProvider.generateAudio(...)            Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift:160
  │   wraps text into GenerationContext(phrase:instruct:)
  ▼
[2] GenerationContext                                  Sources/SwiftVoxAlta/GenerationContext.swift:58
  │   envelope: phrase + metadata (instruct). NO language/accent field here.
  ▼
[3] Route selection                                    VoxAltaVoiceProvider.swift:200
  ├── Route 1: preset speaker (id matches presetSpeakers) → generateWithPresetSpeaker()
  └── Route 2: cloned voice (cache lookup) → VoiceLockManager.generateAudio()
  ▼
[4] VoiceLockManager.generateAudio(context:...)        Sources/SwiftVoxAlta/VoiceLockManager.swift:147
  │   extracts instruct, forwards text + language (default "en") + clone prompt
  │   auto-chunks long text at sentence boundaries (splitAtSentences)
  ▼
[5] Qwen3TTSModel.generateWithClonePrompt(language:)   mlx-audio-swift .../Qwen3TTS/Qwen3TTS.swift:244
  │   builds codec prefill, looks up language token, runs the AR loop
  ▼
[6] AudioConversion.mlxArrayToWAVData(...)             Sources/SwiftVoxAlta/AudioConversion.swift
      → 24kHz / 16-bit / mono WAV Data
```

In every layer the language is just a **string passed straight through**. The
defaults are `language: "en"` at VoiceLockManager.swift:69/150/203 and the
caller's `languageCode`. Nothing translates, normalizes, or branches on it.

## Where the American accent comes from

There is **no "American English" setting anywhere**. The model has exactly one
English. On-disk `codec_language_id` keys (verified from the downloaded
`Qwen3-TTS-12Hz-1.7B-CustomVoice` config) are full names only:

```
chinese, english, german, italian, portuguese, spanish, japanese, korean,
french, russian, beijing_dialect, sichuan_dialect
```

No `en-US`, no `en-GB`, no ISO codes. So the accent cannot be selected by the
language code. It is introduced by three compounding mechanisms, in order of
impact:

### 1. `"en"` never resolves → NO language token is emitted at all  ⚠️ primary bug
- VoxAlta passes the raw string `"en"` down to the model (it never calls the
  resolver — confirmed: `resolveLanguage` is **dead code**, defined at
  `Qwen3TTS.swift:861` and called from nowhere in the repo).
- In the model, `languageId = langMap["en".lowercased()]` → `langMap` keys are
  `english`/`chinese`/... so `langMap["en"]` is **nil**
  (`Qwen3TTS.swift:308-309` for clone path, `:1490-1491` for base path).
- With `languageId == nil`, the codec prefill takes the **"nothink" branch with
  no language token** (`Qwen3TTS.swift:1504-1510`). The model gets *zero*
  explicit language conditioning and free-runs on its training prior — which for
  English is American-dominant. **This is the most likely leak.**
- Passing `"english"` instead of `"en"` would at least inject the english
  language token. Wiring `resolveLanguage("en") → "english"` into the VoxAlta
  call sites is the cheapest correctness fix.

### 2. Preset speakers are literally American (Route 1)
`VoxAltaVoiceProvider.swift:46-60` — `aiden` is "Sunny American male voice";
`ryan` is unlabeled but American-leaning. Picking these *is* picking an American
accent. (The Chinese/Japanese/Korean presets carry their own accents.)

### 3. Clone-anchor dilution on long text (Route 2)
For cloned voices the accent lives entirely in the clone prompt's reference
audio. If the `.vox` was cast from an American (or American-leaning Qwen)
reference, output is American. Worse, long generations drift *away* from the
clone anchor toward the model's American prior — this is the documented "TRIM
ratio drift / ICL anchor dilution" that the sentence auto-chunking
(VoiceLockManager.swift:262-313) was added to fight.

## What this means for fixing it

- A regional accent **cannot** be requested via `languageCode` — the model has no
  representation for it. `"en-GB"` would resolve to `langMap["en-gb"] = nil`,
  i.e. the same no-token free-run as `"en"`.
- To get a non-American English accent you must control the **clone reference
  audio** (cast the `.vox` from a reference in the target accent) and/or steer
  via the `instruct` hint (e.g. "British RP accent") — though instruct steering
  of accent is weak and unreliable in Qwen3-TTS.
- First, fix mechanism #1: normalize the language code to the model's internal
  name before it reaches `generateWithClonePrompt`/`generate`, so at least the
  english language token is actually injected.
```
