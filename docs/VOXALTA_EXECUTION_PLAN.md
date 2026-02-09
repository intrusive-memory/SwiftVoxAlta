# VoxAlta Execution Plan

## Architecture Overview

VoxAlta is a thin library that provides Qwen3-TTS voice design and cloning capabilities
as a `VoiceProvider` for SwiftHablare. It does not parse scripts, does not own persistence,
and does not manage UI. It ingests structured data from SwiftCompartido, transforms it
through character analysis (SwiftBruja) and voice synthesis (Qwen3-TTS via forked
mlx-audio-swift), and returns audio data.

```
SwiftCompartido (input)     SwiftHablare (output contract)     Produciesta (storage)
GuionDocumentModel    →     VoiceProvider protocol        →    SwiftData / TypedDataStorage
GuionElementModel           generateAudio(text:voiceId:)
ElementType                 fetchVoices(languageCode:)
CharacterVoiceMapping       Voice, ProcessedAudio
```

### Dependencies

- `SwiftHablare` — VoiceProvider protocol, GenerationService, VoiceProviderRegistry
- `SwiftCompartido` — GuionDocumentModel, GuionElementModel, ElementType, CharacterVoiceMapping
- `SwiftBruja` — LLM inference for character analysis
- `mlx-audio-swift` (forked to intrusive-memory) — Qwen3-TTS inference
- `AVFoundation` — Audio format conversion

### What VoxAlta Provides

1. **VoiceProvider implementation** — text + voiceId → audio Data (Qwen3-TTS Base model cloning)
2. **Voice design API** — character evidence → CharacterProfile → voice candidates → locked voice
3. **VoiceProviderDescriptor** — for auto-registration with SwiftHablare's registry

### What VoxAlta Does NOT Provide

- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Streaming playback (SwiftHablare / app layer)

---

## External Dependencies

### mlx-audio-swift Fork

The mlx-audio-swift fork work (Base model, voice cloning, instruct parameter, upstream PR)
has its own execution plan at `/Users/stovak/Projects/mlx-audio-swift/EXECUTION_PLAN.md`.

| VoxAlta Sprint | Requires from Fork | Fork Sprint |
|----------------|-------------------|-------------|
| Sprint 1 (Package Setup) | Fork exists and builds | Fork Sprint 1 (COMPLETED) |
| Sprint 2 (Model Management) | Fork exists and builds | Fork Sprint 1 (COMPLETED) |
| Sprint 4 (Voice Design & Lock) | Voice cloning API available | Fork Sprint 3 (Voice Cloning) |

**Sprint 1 and Sprint 2 can start immediately** — the fork exists and builds.
**Sprint 4 blocks on the fork's voice cloning work** completing.

### SwiftHablare Integration

The QwenTTSEngine removal and VoxAlta wiring into SwiftHablare has its own execution plan
at `/Users/stovak/Projects/SwiftHablare/EXECUTION_PLAN.md`.

| SwiftHablare Sprint | Requires from VoxAlta | VoxAlta Sprint |
|---------------------|----------------------|----------------|
| Sprint 1 (Remove QwenTTSEngine) | Nothing | — |
| Sprint 2 (Wire in VoxAlta) | VoiceProvider complete | VoxAlta Sprint 5 |

**SwiftHablare Sprint 1 can start immediately** — it's purely removing dead code.
**SwiftHablare Sprint 2 blocks on VoxAlta Sprint 5** completing.

---

## Execution Order & Dependency Graph

```
[Fork Sprint 1: COMPLETED] ──→ Sprint 1: Package setup + types
                                         │
                                Sprint 2: Model management
                                         │
                                Sprint 3: Character analysis
                                         │
                    ─────────────────────┴──── converge ────
[Fork Sprint 3: Voice cloning] ──→ Sprint 4: Voice design + lock
                                   Sprint 5: VoiceProvider
                                   Sprint 6: Integration & SwiftHablare swap
```

| Order | Sprint | Risk | Depends On | Rationale |
|-------|--------|------|------------|-----------|
| 1 | **Package setup + types + repo** | Low | Fork Sprint 1 (done) | Establish buildable package, enable CI early |
| 2 | **Model management** | Low | Fork Sprint 1 (done) | Actor wrapping model lifecycle, needed before VoiceProvider |
| 3 | **Character analysis** | Low | Sprint 1 | SwiftBruja integration, independent of TTS models |
| 4 | **Voice design + lock** | Medium | Sprint 3, Fork Sprint 3 | First sprint wiring TTS and analysis together |
| 5 | **VoiceProvider** | Low | Sprint 4, Sprint 2 | Wraps everything into the SwiftHablare contract |
| 6 | **Integration & CI** | Low | Sprint 5 | Final assembly and SwiftHablare swap |

### Parallel Opportunities

Sprints 1 and 2 can start immediately in parallel (both depend only on the completed fork).
Sprint 3 depends on Sprint 1 only.

---

## Sprint 1: Package Setup + Types

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`

### 1.1 — Create GitHub repository
- Initialize git repo for SwiftVoxAlta
- Create repo in intrusive-memory org on GitHub
- Push initial commit with README and .gitignore
- **Test**: Repo exists at `github.com/intrusive-memory/SwiftVoxAlta`

### 1.2 — Add CI workflow
- Create `.github/workflows/tests.yml`
- Runner: `macos-26`, Swift 6.2+
- Build with `xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS'`
- Run unit tests (integration tests marked as local-only due to model size)
- **Test**: CI workflow runs on push to main/development branches

### 1.3 — Create Package.swift
- Define SwiftVoxAlta package with `SwiftVoxAlta` library target
- Dependencies: SwiftHablare, SwiftCompartido, SwiftBruja, mlx-audio-swift (forked from intrusive-memory)
- Platform requirements: macOS 26+, iOS 26+, Swift 6.2+
- Add test target `SwiftVoxAltaTests`
- **Test**: `xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS'` succeeds

### 1.4 — Define VoxAlta error types
- Create `Sources/SwiftVoxAlta/VoxAltaError.swift`
- `VoxAltaError` enum: voiceDesignFailed, cloningFailed, modelNotAvailable, voiceNotLoaded,
  profileAnalysisFailed, insufficientMemory, audioExportFailed
- Conform to `Error`, `LocalizedError`, `Sendable`
- **Test**: All error cases compile, have non-empty errorDescription

### 1.5 — Define CharacterProfile and CharacterEvidence types
- Create `Sources/SwiftVoxAlta/CharacterProfile.swift`
- `CharacterProfile`: name, gender (enum), ageRange, description, voiceTraits ([String]), summary
- `CharacterEvidence`: characterName, dialogueLines ([String]), parentheticals ([String]),
  sceneHeadings ([String]), actionMentions ([String])
- Conform to `Codable`, `Sendable`
- **Test**: Types compile, round-trip through JSONEncoder/JSONDecoder

### 1.6 — Define VoiceLock and VoxAltaConfig types
- Create `Sources/SwiftVoxAlta/VoiceLock.swift`
- `VoiceLock`: characterName, clonePromptData (Data), designInstruction (String), lockedAt (Date)
- Create `Sources/SwiftVoxAlta/VoxAltaConfig.swift`
- `VoxAltaConfig`: designModel (String), renderModel (String), analysisModel (String),
  candidateCount (Int), outputFormat (enum: wav/aiff/m4a)
- Conform to `Codable`, `Sendable`
- **Test**: Types compile, round-trip through JSONEncoder/JSONDecoder

### 1.7 — Implement character evidence extraction
- Create `Sources/SwiftVoxAlta/CharacterEvidenceExtractor.swift`
- Function that accepts `[GuionElementModel]` (sorted elements from SwiftCompartido)
- Walk elements sequentially: when `.character` is found, collect subsequent `.dialogue`
  and `.parenthetical` elements until next `.character` or non-dialogue element
- Track scene headings and action lines mentioning each character name
- Return `[String: CharacterEvidence]` keyed by character name
- **Test**: Given sample elements with 2 characters, extract correct dialogue counts and parentheticals

### Exit Criteria
- GitHub repo exists at `github.com/intrusive-memory/SwiftVoxAlta`
- CI workflow defined and runs
- Package.swift builds with all dependencies resolving
- All types compile, conform to Codable + Sendable, round-trip correctly
- Character evidence extraction works for sample input

---

## Sprint 2: Model Management

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`

### 2.1 — Implement VoxAltaModelManager actor
- Create `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`
- Actor managing Qwen3-TTS model lifecycle via mlx-audio-swift's `TTSModelUtils.loadModel()`
- Methods: `loadModel(repo:)`, `unloadModel()`, `isModelLoaded`
- Cache loaded `SpeechGenerationModel` instance in memory — return cached on subsequent calls
- Support VoiceDesign (1.7B) and Base (1.7B, 0.6B) model variants
- **Test**: Load a model, verify cached on second access; unload, verify nil

### 2.2 — Implement memory validation
- Add `validateMemory(forModelSizeBytes:)` method to VoxAltaModelManager
- Check available system memory before loading models
- TTS models: ~2GB for 1.7B-bf16, ~1GB for 0.6B-bf16, less for quantized
- Throw `VoxAltaError.insufficientMemory` if available < required * 1.5 (headroom for KV cache)
- **Test**: Validation passes with sufficient RAM, throws with artificially low threshold

### Exit Criteria
- VoxAltaModelManager actor compiles and conforms to Sendable
- Model loading caches correctly
- Memory validation prevents loading when insufficient RAM

---

## Sprint 3: Character Analysis

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`

### 3.1 — Implement CharacterAnalyzer
- Create `Sources/SwiftVoxAlta/CharacterAnalyzer.swift`
- Accept `CharacterEvidence`, call `SwiftBruja.query()` with tightly-scoped prompt
- Prompt template: "Analyze this character for TTS voice design. Use ONLY evidence from the text.
  Given dialogue, parentheticals, scene context — produce gender, ageRange, voiceTraits, summary."
- Parse LLM JSON response into `CharacterProfile` using `Bruja.query(as: CharacterProfile.self)`
- **Test**: Given evidence with clear gender/age signals, verify profile matches expectations

### 3.2 — Implement parenthetical-to-instruct table mapping
- Create `Sources/SwiftVoxAlta/ParentheticalMapper.swift`
- Static dictionary mapping common parentheticals to TTS instruct strings:
  (whispering) → "speak in a whisper", (shouting) → "speak loudly and forcefully",
  (sarcastic) → "speak with a sarcastic tone", (beat) → nil (insert pause, not vocal),
  (to herself) → "speak quietly, as if talking to oneself", etc.
- Return `nil` for blocking/physical directions (turning, walking, etc.)
- **Test**: Map 10+ common parentheticals, verify correct instruct strings; verify (beat) returns nil

### 3.3 — Implement LLM fallback for unusual parentheticals
- Add fallback path in `ParentheticalMapper` for parentheticals not in the table
- Call SwiftBruja with: "Classify this parenthetical as 'vocal' or 'blocking'. If vocal,
  provide a TTS instruction. Parenthetical: '{text}'"
- Return instruct string for vocal, nil for blocking
- **Test**: Pass unusual parenthetical like "(with barely contained rage)", verify returns vocal instruct

### Exit Criteria
- CharacterAnalyzer produces valid CharacterProfile from evidence
- ParentheticalMapper handles all common parentheticals
- LLM fallback classifies unusual parentheticals correctly
- All tests pass

---

## Sprint 4: Voice Design & Lock

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`
> **Requires**: Sprint 3 (character analysis) and Fork Sprint 3 (voice cloning)

### 4.1 — Implement VoiceDesigner
- Create `Sources/SwiftVoxAlta/VoiceDesigner.swift`
- Accept `CharacterProfile`, compose voice description from profile's summary + voiceTraits
- Call Qwen3-TTS VoiceDesign via VoxAltaModelManager to generate a single reference audio clip
- Return candidate audio as `Data` (WAV bytes)
- **Test**: Given a character profile, generate 1 voice candidate, verify valid non-empty WAV

### 4.2 — Implement multi-candidate voice generation
- Add `generateCandidates(profile:count:)` method to VoiceDesigner
- Generate N candidates (default 3) with same description, different seeds/temperature
- Return `[Data]` array of WAV candidates
- **Test**: Generate 3 candidates, verify each is valid WAV, verify they differ from each other

### 4.3 — Implement VoiceLock creation
- Create `Sources/SwiftVoxAlta/VoiceLockManager.swift`
- Accept selected candidate audio `Data`
- Call `create_voice_clone_prompt()` from fork Sprint 3.4 to extract speaker embedding
- Package into `VoiceLock` struct: characterName, clonePromptData, designInstruction, lockedAt
- **Test**: Create VoiceLock from candidate WAV, verify clonePromptData is non-empty, verify Codable round-trip

### 4.4 — Implement VoiceLock-based generation
- Add `generateAudio(text:voiceLock:instruct:language:)` method to VoiceLockManager
- Deserialize clone prompt from VoiceLock.clonePromptData
- Generate audio using `generate(clonePrompt:)` from fork Sprint 3.5
- Return audio as `Data` (WAV bytes)
- **Test**: Generate 3 different texts with same VoiceLock, verify consistent voice identity

### Exit Criteria
- VoiceDesigner produces valid WAV candidates from character profiles
- Multi-candidate generation produces distinct but same-character voices
- VoiceLock round-trips through Codable
- VoiceLock-based generation produces consistent voice identity

---

## Sprint 5: VoiceProvider Implementation

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`
> **Reference**: VoiceProvider protocol in `/Users/stovak/Projects/SwiftHablare/Sources/SwiftHablare/VoiceProvider.swift`

### 5.1 — Implement VoxAltaVoiceProvider shell
- Create `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`
- Conform to `VoiceProvider` protocol (Sendable)
- Set `providerId = "voxalta"`, `displayName = "VoxAlta (On-Device)"`,
  `requiresAPIKey = false`, `mimeType = "audio/wav"`
- Implement `isConfigured()` — return true if at least one model is downloaded
- Stub remaining methods with `fatalError("not implemented")`
- **Test**: Provider instantiates, reports correct metadata, isConfigured returns expected value

### 5.2 — Implement loadVoice and voice cache
- Add in-memory `[String: Data]` dictionary for cached clone prompts
- Implement `loadVoice(id: String, clonePromptData: Data)` — stores in dictionary
- Implement `unloadVoice(id: String)` — removes from dictionary
- Implement `unloadAllVoices()` — clears dictionary
- **Test**: Load a clone prompt, verify cached; unload, verify removed; loadAll/unloadAll works

### 5.3 — Implement fetchVoices
- Return currently loaded voices as `[Voice]`
- Each loaded voice ID maps to a `Voice` struct with id, name (= id), providerId = "voxalta"
- Accept optional metadata (gender, language) via `loadVoice` parameters
- **Test**: Load 2 voices with names "ELENA" and "MARCUS", fetchVoices returns 2 correct Voice objects

### 5.4 — Implement generateAudio
- Look up voiceId in cached clone prompts
- If not found, throw `VoxAltaError.voiceNotLoaded(voiceId)`
- Deserialize clone prompt, call VoiceLockManager.generateAudio with clone prompt
- Convert MLXArray output to WAV Data (24kHz, 16-bit PCM)
- **Test**: Load a voice, generate audio for a sentence, verify valid WAV Data returned

### 5.5 — Implement generateProcessedAudio
- Call generateAudio to get raw WAV Data
- Use AVFoundation to measure actual duration
- Use AudioProcessor from SwiftHablare to trim silence from start/end
- Return `ProcessedAudio` with audioData, durationSeconds, trimmedStart, trimmedEnd, mimeType
- **Test**: ProcessedAudio has non-zero durationSeconds, trimmed values are >= 0

### 5.6 — Implement estimateDuration and isVoiceAvailable
- `estimateDuration`: count words in text, divide by 150 (words per minute), return TimeInterval
- `isVoiceAvailable`: return true if voiceId exists in loaded voice cache
- **Test**: estimateDuration("hello world") returns ~0.8s; isVoiceAvailable returns true/false correctly

### 5.7 — Implement VoiceProviderDescriptor
- Create `Sources/SwiftVoxAlta/VoxAltaProviderDescriptor.swift`
- Build `VoiceProviderDescriptor` with id "voxalta", factory creating VoxAltaVoiceProvider
- `isEnabledByDefault = false`, `requiresConfiguration = true` (needs model download)
- **Test**: Descriptor creates valid provider, registers with VoiceProviderRegistry.shared

### 5.8 — Implement SwiftUI configuration view
- Create `Sources/SwiftVoxAlta/VoxAltaConfigurationView.swift`
- SwiftUI view showing: model download status per variant (VoiceDesign 1.7B, Base 1.7B, Base 0.6B)
- Download/delete buttons per model
- Memory usage indicator (available vs. required)
- Quality toggle (1.7B vs 0.6B Base for draft renders)
- Wire into VoiceProviderDescriptor's `configurationPanel`
- **Test**: View renders without crashes, shows download status

### Exit Criteria
- VoxAltaVoiceProvider conforms to VoiceProvider protocol
- All protocol methods implemented and tested
- VoiceProviderDescriptor registers successfully
- Configuration view renders

---

## Sprint 6: End-to-End Integration Tests

> **Working directory**: `/Users/stovak/Projects/SwiftVoxAlta`

### 6.1 — End-to-end integration test
- Create `Tests/SwiftVoxAltaIntegrationTests/FullPipelineTests.swift`
- Build a mock `[GuionElementModel]` with 2 characters, 3 dialogue lines each, 1 parenthetical
- Run full pipeline: extract evidence → analyze characters → design voices →
  lock voices → render all lines via VoiceProvider
- Verify: all audio Data objects are valid WAV, non-zero duration
- **Test**: Full pipeline completes without error, produces audio for every dialogue line

### 6.2 — Voice consistency validation
- Generate multiple lines with the same VoiceLock
- Verify audio characteristics remain consistent (sample rate, non-empty, valid WAV)
- Test with different text lengths (short phrase, full sentence, long paragraph)
- **Test**: All generated audio is valid and uses same voice identity

### 6.3 — Error path testing
- Test VoiceProvider with unloaded voice → throws `VoxAltaError.voiceNotLoaded`
- Test model loading with invalid repo → throws `VoxAltaError.modelNotAvailable`
- Test character analysis with empty evidence → handles gracefully
- **Test**: All error paths return expected errors, no crashes

### Exit Criteria
- Full pipeline integration test passes end-to-end
- Voice consistency verified across multiple generations
- Error paths tested and handled correctly

---

## Resolved Questions

1. **VoiceLock persistence**: VoxAlta returns clone prompt as `Data`. The app (Produciesta)
   stores it as a `TypedDataStorage` with mimeType `"application/x-clone-prompt"` attached
   to the `GuionDocumentModel`. The voice design reference clip (the audio candidate the user
   picked) is stored as normal `"audio/wav"` TypedDataStorage. `CharacterVoiceMapping` ties
   character name → VoiceURI → the UUID of the stored clone prompt. VoxAlta never touches
   SwiftData directly.

2. **Voice ID scheme**: Two-step pattern. Before rendering, the app calls
   `voxalta.loadVoice(id: "ELENA", clonePromptData: data)` which caches the clone prompt
   in memory. Then `generateAudio(text:voiceId:"ELENA")` uses the cached prompt.
   The voiceId is the character name (or any string key). The VoiceURI stored in
   `CharacterVoiceMapping` follows the pattern `"voxalta://ELENA"`.

3. **Existing QwenTTSEngine**: VoxAlta replaces the existing QwenTTSVoiceProvider and
   QwenTTSEngine in SwiftHablare. They are incomplete and incorrectly implemented.
   The removal and wiring is handled in SwiftHablare's own execution plan at
   `/Users/stovak/Projects/SwiftHablare/EXECUTION_PLAN.md`.

4. **Configuration view**: Minimal, on-device only:
   - Model download status (which Qwen3-TTS models are downloaded, size on disk)
   - Download/delete buttons per model variant (VoiceDesign 1.7B, Base 1.7B, Base 0.6B)
   - Memory usage indicator (available vs. required)
   - Quality toggle (1.7B vs 0.6B Base for draft renders)
   - No API key required.

5. **Batch rendering**: No special batch API. VoxAltaModelManager actor keeps the model
   loaded in memory between calls. Calling generateAudio() N times in sequence is efficient —
   the model loads on first call, stays cached for subsequent calls. The app can parallelize
   with TaskGroup if memory allows. Adding a batch API would violate the thin library goal.
