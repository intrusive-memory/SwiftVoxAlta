# TODO — Optional Per-Language Voices in SwiftVoxAlta (middle layer)

**Status:** ✅ **FULLY UNBLOCKED — vox-format 0.4.0 shipped (tag `v0.4.0`, 2026-06-08).**
SwiftVoxAlta is the middle layer of a 3-repo coordinated effort. The gate that previously held
Items 2 & 3 is now satisfied: vox-format 0.4.0 landed `EmbeddingEntry.language` +
`sampleAudioData(for:language:)` / `clonePromptData(for:language:)` matchers (plus the optional
`sampleAudioLanguages(for:)` / `clonePromptLanguages(for:)` discovery helpers). All three items
can proceed now. Sequencing reduces to: **bump the vox-format pin `0.3.1` → `0.4.0` here FIRST**
(`Package.swift:96`), then land Item 1 (load-bearing quality fix, no vox-format dependency),
then Items 2 & 3 (write/read, which use the new matchers).

**Author:** research pass, 2026-06-08. **Status updated:** 2026-06-08 (vox-format 0.4.0 released; pin bump unblocked).
**Sibling contracts (read these — this plan is consistent with them):**
- `/Users/stovak/Projects/vox-format/TODO.md` — adds optional `EmbeddingEntry.language` (BCP 47) + language-aware read matchers, schema 0.3.0 → 0.4.0.
- `/Users/stovak/Projects/SwiftEchada/TODO.md` — adds `--language` to casting, threads it to inference, consumes the writers below.

---

## Problem statement

The user tested Spanish TTS and got bad **pronunciation**. Root cause on the casting side:
`VoiceLockManager.createLock` **hardcodes `language: "en"`** when it extracts the clone prompt
(`Sources/SwiftVoxAlta/VoiceLockManager.swift:91`). The clone prompt is **load-bearing** — it
drives synthesis — so extracting it with the wrong language tag misaligns the tokenizer against
non-English reference audio and degrades quality. Separately, a `.vox` can today carry only a
single language-less clone prompt + sample audio per model; there is no way to store a Spanish
clone prompt alongside an English one for the same model.

## Locked decisions (user, 2026-06-08 — do not relitigate)

1. **Path scheme — language segment APPENDED under `embeddings/`. NO `samples/` tree.**
   - Default (language-less, == current behavior):
     `embeddings/qwen3-tts/<slug>/sample-audio.wav` and `embeddings/qwen3-tts/<slug>/clone-prompt.bin`
   - Per-language:
     `embeddings/qwen3-tts/<slug>/<lang>/sample-audio.wav` and `embeddings/qwen3-tts/<slug>/<lang>/clone-prompt.bin`
2. **Scope = BOTH** per-language clone prompts AND per-language sample audio. Clone prompt is
   mandatory (it drives synthesis); sample audio is the preview.
3. **SwiftVoxAlta is in scope NOW.** Languages use **BCP 47** (e.g. `en-US`, `es`, `fr-FR`),
   consistent with vox-format's existing `language` fields.
4. **Fallback semantics (must match vox-format verbatim):** lookup `(model, language)` →
   exact match → base-language fallback (`fr-FR` → `fr`) → default/language-less → `nil`.
   `language == nil` or `language == "default"` behaves **exactly as today** (full backward compat).

---

## What is ALREADY plumbed (confirmed — do NOT re-plumb)

The generation side already threads language end-to-end. Only `createLock` is the gap.

- `VoiceLockManager.generateAudio(context:..., language: String = "en", ...)` — `VoiceLockManager.swift:144`.
- `VoiceLockManager.generateAudio(text:..., language: String = "en", ...)` — `VoiceLockManager.swift:197`; forwarded into `qwenModel.generateWithClonePrompt(..., language: language, ...)` at `:289` and `:313`.
- mlx-audio-swift `Qwen3TTSModel.createVoiceClonePrompt(refAudio:refText:language:)` already takes `language` (default `"auto"`) — `mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSVoiceClonePrompt.swift:177-181`. **Used by `createLock` at `VoiceLockManager.swift:88-92`, which passes the hardcoded `"en"`.**

So **only `createLock` hardcodes "en"** within the SwiftVoxAlta clone-prompt-creation path.

---

## 1. `createLock` language parameter (load-bearing quality fix — UNBLOCKED NOW)

**File:** `Sources/SwiftVoxAlta/VoiceLockManager.swift`

### Current state
- Signature (`:57-64`) has NO `language` param:
  ```swift
  public static func createLock(
    characterName: String,
    candidateAudio: Data,
    designInstruction: String,
    modelManager: VoxAltaModelManager,
    sampleSentence: String? = nil,
    modelRepo: Qwen3TTSModelRepo = .base1_7B
  ) async throws -> VoiceLock
  ```
- Hardcodes language at `:88-92`:
  ```swift
  clonePrompt = try qwenModel.createVoiceClonePrompt(
    refAudio: refAudio,
    refText: sampleSentence ?? defaultReferenceSampleText,
    language: "en"          // ← :91 hardcoded
  )
  ```
- `refText` is just passed through (`sampleSentence ?? defaultReferenceSampleText`, `:90`).
  **Confirmed: `createLock` does NOT generate or translate the reference sentence — echada
  supplies it via `sampleSentence`.** So echada is responsible for handing a same-language
  `sampleSentence`; `createLock` only needs to forward the matching `language` tag so the
  tokenizer aligns the (echada-provided) `refText` correctly. No sentence-generation work here.

### Checklist
- [ ] Add `language: String = "en"` to `createLock` — **append it LAST** in the parameter list
      (after `modelRepo`) so the existing positional/labelled call sites in DigaEngine keep
      compiling unchanged:
      ```swift
      public static func createLock(
        characterName: String,
        candidateAudio: Data,
        designInstruction: String,
        modelManager: VoxAltaModelManager,
        sampleSentence: String? = nil,
        modelRepo: Qwen3TTSModelRepo = .base1_7B,
        language: String = "en"        // NEW, defaulted → backward compatible
      ) async throws -> VoiceLock
      ```
- [ ] Forward it at `:91`: replace `language: "en"` with `language: language`.
- [ ] Update the doc comment (`:46-56`) to document the new `language` parameter.
- [ ] (Consider, see Open Questions Q1) store the language on the returned `VoiceLock`. Today
      `VoiceLock` (`Sources/SwiftVoxAlta/VoiceLock.swift`) carries `characterName`,
      `clonePromptData`, `designInstruction`, `lockedAt` (`VoiceLockManager.swift:114-119`).
      Not strictly required for the fix; the language is consumed at extraction time.

### Internal call sites of `createLock` (default keeps them compiling; optional to thread language)
Both are on the **synthesis/render path** in DigaCLICore, extracting a clone prompt at runtime
from `.vox` source/reference audio. With `language` defaulted to `"en"` they compile unchanged.
They SHOULD eventually pass the synthesis language so runtime extraction matches, but that is a
DigaCLICore concern, not required for the casting-quality fix:
- [ ] `Sources/DigaCLICore/DigaEngine.swift:427` — extract-from-reference-audio path. Has a
      `resolvedBaseModelRepo` in scope; thread the engine's request language here if/when DigaCLICore exposes one.
- [ ] `Sources/DigaCLICore/DigaEngine.swift:695` — extract-from-`.vox`-source-audio path (per-model). Same note.

---

## 2. `VoxExporter` language-aware WRITE paths (UNBLOCKED — vox-format 0.4.0 shipped)

**File:** `Sources/SwiftVoxAlta/VoxExporter.swift`

All four pieces gain an optional `language: String? = nil`. `nil` → current language-less path
(byte-for-byte identical to today). Non-nil → insert the `<lang>` segment AND pass
`"language": "<bcp47>"` into the `vox.add(..., metadata:)` dict so vox-format populates
`EmbeddingEntry.language` (the metadata field is vox-format's source of truth for the matcher;
the path segment is human-browsable convention).

### 2a. Path helpers
- [ ] `clonePromptPath(for:)` (`VoxExporter.swift:19-21`) → add `language: String? = nil`:
  ```swift
  static func clonePromptPath(for repo: Qwen3TTSModelRepo, language: String? = nil) -> String {
    let base = "embeddings/qwen3-tts/\(modelSizeSlug(for: repo))"
    if let language, language != "default" {
      return "\(base)/\(language)/clone-prompt.bin"
    }
    return "\(base)/clone-prompt.bin"
  }
  ```
- [ ] `sampleAudioPath(for:)` (`VoxExporter.swift:25-27`) → identical treatment, filename
      `sample-audio.wav`.
- [ ] Treat `language == "default"` the same as `nil` (resolves to the language-less path) to
      match the vox-format fallback contract.

### 2b. Write operations
- [ ] `addClonePrompt(to:data:modelRepo:)` (`VoxExporter.swift:40-55`) → add `language: String? = nil`
      (append last). Pass it to `clonePromptPath(for:language:)`. Inject the language into the
      metadata dict AND make the `"key"` unique per language so the manifest's derived key does
      not collide with the default:
  ```swift
  public static func addClonePrompt(
    to vox: VoxFile,
    data: Data,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    language: String? = nil
  ) throws {
    let slug = modelSizeSlug(for: modelRepo)
    let langSuffix = (language != nil && language != "default") ? "-\(language!)" : ""
    var metadata: [String: String] = [
      "key": "qwen3-tts-\(slug)\(langSuffix)-clone-prompt",
      "model": modelRepo.rawValue,
      "engine": "qwen3-tts",
      "format": "bin",
      "description": "Clone prompt for voice cloning (\(slug)\(langSuffix))",
    ]
    if let language, language != "default" { metadata["language"] = language }
    try vox.add(data, at: clonePromptPath(for: modelRepo, language: language), metadata: metadata)
  }
  ```
- [ ] `addSampleAudio(to:data:modelRepo:)` (`VoxExporter.swift:66-81`) → identical treatment
      (`format: "wav"`, key suffix `-sample-audio`, path via `sampleAudioPath(for:language:)`).

### 2c. URL-based update wrappers (thread language through, defaulted)
- [ ] `updateClonePrompt(in:clonePromptData:modelRepo:)` (`VoxExporter.swift:96-111`) calls
      `addClonePrompt` at `:103`. Add `language: String? = nil` to the wrapper signature and
      forward it.
- [ ] `updateSampleAudio(in:sampleAudioData:modelRepo:)` (`VoxExporter.swift:123-138`) calls
      `addSampleAudio` at `:130`. Same.

### 2d. Existing tests to update (signatures only; behavior unchanged when language omitted)
- `Tests/SwiftVoxAltaTests/VoxExporterTests.swift` calls `clonePromptPath(for:)` /
  `sampleAudioPath(for:)` / `addClonePrompt` / `addSampleAudio` in ~20 places (`:21-212`). With
  defaulted params these keep compiling; ADD new cases (see §4) rather than rewriting them.

---

## 3. `VoxImporter` language-aware READ (UNBLOCKED — vox-format 0.4.0 shipped)

**File:** `Sources/SwiftVoxAlta/VoxImporter.swift`

### Current state
- `VoxImportResult` (`:5-24`) carries single `clonePromptData: Data?` (`:13`) and
  `sampleAudioData: Data?` (`:15`).
- `importVox(from:modelQuery:)` (`:40-77`) calls the **language-less** matchers:
  `voxFile.clonePromptData(for: modelQuery)` (`:47`) and
  `voxFile.sampleAudioData(for: modelQuery)` (`:50`).

### Design: add a language-aware overload (keep the existing one for source compat)
Recommended surface — a new overload that threads `language` into the new vox-format matchers
and applies the locked fallback. Produciesta (downstream consumer, **OUT OF SCOPE — user owns
it**) will call this to SELECT a language; we only need to EXPOSE it.

- [ ] Add `language: String? = nil` to a new overload:
  ```swift
  public static func importVox(
    from url: URL,
    modelQuery: String = Qwen3TTSModelRepo.base1_7B.slug,
    language: String? = nil
  ) throws -> VoxImportResult
  ```
  - When `language == nil` → call existing language-less matchers (identical to today).
  - When non-nil → call vox-format's new
    `voxFile.clonePromptData(for: modelQuery, language: language)` and
    `voxFile.sampleAudioData(for: modelQuery, language: language)` (these encapsulate the
    exact→base-language→default→nil fallback per the locked contract — SwiftVoxAlta must NOT
    re-implement fallback; it delegates to vox-format).
- [ ] Keep the existing `importVox(from:modelQuery:)` (`:40`) as a thin forwarder
      (`language: nil`) so all current callers and tests compile unchanged.
- [x] Add `availableLanguages: [String]` to `VoxImportResult` so Produciesta can discover what
      languages a `.vox` carries. Wraps vox-format's discovery helper
      (`sampleAudioLanguages(for:)`). Discovery only — fallback resolution stays in vox-format.
      (A "resolved language" field is intentionally NOT exposed here; if a consumer needs to know
      which language a matcher landed on, that belongs in a different part of the stack — the
      matcher itself should return the tag, not be re-derived in SwiftVoxAlta.)

### Internal call sites of `importVox` (default keeps them compiling)
- [ ] `Sources/DigaCLICore/DigaEngine.swift:410` (`modelQuery: resolvedModelSlug`).
- [ ] `Sources/DigaCLICore/DigaEngine.swift:683` (no modelQuery).
- [ ] `Sources/DigaCLICore/DigaCommand.swift:286` (no modelQuery).
- Tests: `Tests/DigaTests/DigaVoxIntegrationTests.swift:91`,
  `Tests/SwiftVoxAltaTests/VoxImporterTests.swift` (multiple). All keep compiling with the
  defaulted overload.

---

## Coordinates with

### Consumes (upstream) — vox-format 0.4.0 (`/Users/stovak/Projects/vox-format`) — ✅ SHIPPED
SwiftVoxAlta items 2 and 3 depended on these; all landed in vox-format 0.4.0 (tag `v0.4.0`):
- `EmbeddingEntry.language: String?` (new optional field; metadata source of truth) — vox-format TODO §5, `VoxManifest.swift:398`.
- Reader matchers with the locked fallback:
  - `VoxFile.sampleAudioData(for query: String, language: String?) -> Data?` — vox-format TODO §3a, `VoxFile+ModelQuery.swift:140`.
  - `VoxFile.clonePromptData(for query: String, language: String?) -> Data?` — vox-format TODO §3c, `VoxFile+ModelQuery.swift:113`.
  - (optional) `VoxFile.sampleAudioLanguages(for query: String) -> [String]` discovery helper — vox-format TODO §3a.
- Writer: `VoxFile.add(_:at:metadata:)` already accepts arbitrary metadata; vox-format's
  AutoManifest (`VoxFile+AutoManifest.swift:68,91`) must read `metadata["language"]` and keep
  `deriveEmbeddingKey` unique across languages. The `<lang>` path segment already keeps keys
  distinct (`qwen3-tts-0.6b-es-...` vs `qwen3-tts-0.6b-...`).

### Consumed by (downstream)
- **SwiftEchada** (`/Users/stovak/Projects/SwiftEchada/TODO.md`):
  - §C calls `VoiceLockManager.createLock(... language:)` from
    `CastVoiceGenerator.swift:274` and `VoiceCommand.swift:84`.
  - §E calls `VoxExporter.addSampleAudio(... language:)` / `addClonePrompt(... language:)` from
    `CastVoiceGenerator.swift:306,308` and `VoiceCommand.swift:109,110`. echada must NOT
    construct `.vox` paths itself — it consumes these writers.
- **Produciesta** (render-side, **OUT OF SCOPE — user owns it**): consumes `VoxImporter`. The
  language-aware `importVox(from:modelQuery:language:)` overload (item 3) EXPOSES language
  selection so Produciesta can later target `es` and pick the `es` clone prompt. No Produciesta
  change in this effort.

### Release / pin sequencing (dependency order)
1. **vox-format 0.4.0** — ✅ DONE. `EmbeddingEntry.language` + the two language-aware matchers
   (and discovery helpers) shipped; tagged `v0.4.0` (2026-06-08).
2. **SwiftVoxAlta** — bump the vox-format pin from `from: "0.3.1"` to `from: "0.4.0"` in
   `Package.swift:96`, then land items 2 + 3 (write/read). Item 1 (`createLock(language:)`) can
   land **independently and immediately** — it has no vox-format dependency. Release/tag SwiftVoxAlta.
3. **echada** — bump its SwiftVoxAlta pin; land §C (consumes `createLock(language:)`) and §E
   (consumes the language-aware writers).

> **Pin note:** the SwiftVoxAlta → vox-format pin is currently a **versioned** pin
> (`sibling("vox-format", remote: ..., from: "0.3.1")`, `Package.swift:93-96`), NOT a branch pin.
> So CI will NOT pick up vox-format `development` automatically — the pin MUST be bumped to
> `0.4.0` once vox-format releases. Locally, the `sibling()` helper prefers the
> `/Users/stovak/Projects/vox-format` checkout when present (`Package.swift:21-30`), so items 2+3
> can be developed locally against the sibling before the release exists — but do not merge until
> the version pin can be bumped, or CI (which forces remote pins) will fail to resolve.

---

## Backward compatibility

- **Item 1:** `language` defaults to `"en"` — the previous hardcoded value. Existing
  `createLock` callers (DigaEngine `:427`, `:695`) compile unchanged and behave identically.
- **Item 2:** `language` defaults to `nil` on every path helper / writer / update wrapper.
  `nil` (and `"default"`) → the exact current language-less path and metadata. With no
  `--language` from echada, `.vox` archives are byte-for-byte identical to today.
- **Item 3:** new `language:` overload defaults to `nil`; the existing
  `importVox(from:modelQuery:)` is preserved as a forwarder. Old `.vox` files (no
  `EmbeddingEntry.language`) resolve via vox-format's default fallback → identical to today.
- All new params are **appended last** to avoid breaking positional call sites. `VoxImportResult`
  gains only optional/defaulted fields if Q2 is adopted (keep `Sendable`).

---

## Test / validation plan

### Make targets (documented — do NOT run as part of planning)
- `make build` → `xcodebuild -scheme diga -destination 'platform=macOS,arch=arm64' build` (runs `resolve` first). `Makefile:23-25`.
- `make test` → `test-unit` + `test-integration`. `Makefile:118`.
- `make test-unit` → `xcodebuild test -scheme SwiftVoxAlta-Package` (DigaTests + SwiftVoxAltaTests, excluding binary integration). `Makefile:67-83`.
- `make resolve` → `xcodebuild -resolvePackageDependencies`. Run after bumping the vox-format pin. `Makefile:18-20`.
- Global rules forbid `swift build` / `swift test` — use the Makefile or XcodeBuildMCP only.
- **Pin re-resolve gotcha (from memory):** after bumping the vox-format pin, `Package.resolved`
  is gitignored and DerivedData `SourcePackages/` may be stale — clear it so xcodebuild fetches 0.4.0.

### Unit tests to ADD (`Tests/SwiftVoxAltaTests/VoxExporterTests.swift`)
- [ ] `clonePromptPath(for:language:)` with `language: nil` → `embeddings/qwen3-tts/1.7b/clone-prompt.bin` (unchanged).
- [ ] `clonePromptPath(for: .base1_7B, language: "es")` → `embeddings/qwen3-tts/1.7b/es/clone-prompt.bin`.
- [ ] `clonePromptPath(for:language:"default")` resolves to the language-less path (== `nil`).
- [ ] Same trio for `sampleAudioPath(for:language:)`.
- [ ] `addClonePrompt(... language: "es")` writes to the `<lang>` path AND sets
      `metadata["language"] == "es"` AND a language-distinct `"key"` (no collision with default).
- [ ] `addClonePrompt` default + `addClonePrompt(language:"es")` for the SAME model coexist
      (two distinct entries, no overwrite).

### Unit / round-trip tests (`Tests/SwiftVoxAltaTests/VoxImporterTests.swift`) — unblocked (vox-format 0.4.0)
- [ ] Write default + `es` clone prompt & sample (via VoxExporter), then
      `importVox(from:modelQuery:language:"es")` returns the `es` data.
- [ ] `importVox(... language: "es")` on a `.vox` with only a default entry → falls back to default (not nil).
- [ ] Base-language fallback: write `fr`, import `language: "fr-FR"` → returns the `fr` data.
- [ ] `importVox(... language: nil)` and the legacy `importVox(from:modelQuery:)` resolve identically.
- [ ] Regression: an existing (no-language) `.vox` fixture imports exactly as before.

### `createLock` language (item 1) — note
`createLock` requires loading a Base model + Metal (clone-prompt extraction), so a true unit
test is impractical on CI (`SwiftVoxAltaTests` are skipped on CI for Metal reasons —
`Makefile:69-71`). Validate via the echada-side Spanish smoke test (echada TODO §"Manual
Spanish smoke test") and locally with `make test-integration` (requires cached model). At
minimum, assert at the type/signature level that `createLock` accepts `language:` and that the
default is `"en"` (can be a compile-time/signature check without invoking the model).

---

## Open questions (non-blocking — defaults adopted; flagged for confirmation)

1. **Store `language` on `VoiceLock`?** Default adopted: **no.** The language is consumed at
   extraction time; `VoiceLock` only needs to carry the resulting `clonePromptData`. Add a
   `language: String?` field only if a downstream consumer needs to know which language a lock
   was extracted for. Does not block item 1.
2. **Expand `VoxImportResult` with `availableLanguages`?** RESOLVED: yes — `availableLanguages:
   [String]` is exposed (wraps vox-format's `sampleAudioLanguages(for:)` discovery helper,
   shipped in 0.4.0). A "resolved language" field is deliberately NOT exposed: the matchers
   return only `Data?`, so deriving which language they resolved to would re-implement
   vox-format's fallback, which the locked contract forbids. That concern belongs to a different
   part of the stack (the matcher returning its resolved tag), not SwiftVoxAlta.
3. **Should DigaEngine's runtime `createLock` calls (`:427`, `:695`) thread a synthesis
   language?** Default adopted: leave at `"en"` default for now (DigaCLICore does not currently
   surface a per-render language to these paths). Track as a follow-up once Produciesta selects
   a language. Does not block this effort.

None of these block starting.
