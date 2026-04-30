# Architecture

SwiftVoxAlta is a **thin TTS VoiceProvider** for the SwiftHablare protocol, plus a CLI (`diga`) that drives the same library directly. It does not parse screenplays, does not analyze characters, and does not own voice creation — those concerns live in `SwiftCompartido`, `SwiftEchada`, and `Produciesta` respectively. SwiftVoxAlta's job ends at "give me a `VoxAltaVoiceProvider` and call `generateAudio(text:voiceId:languageCode:)` to get back WAV `Data`."

## Targets

```
SwiftVoxAlta/
├── Package.swift
├── Sources/
│   ├── SwiftVoxAlta/        ← Library target (the VoiceProvider + types)
│   └── diga/                ← Executable target (CLI; depends on the library)
└── Tests/
    ├── SwiftVoxAltaTests/   ← Library unit tests (Metal-incompatible on CI)
    └── DigaTests/           ← CLI unit + binary integration tests
```

Two products: `SwiftVoxAlta` (library) and `diga` (CLI executable). The library is what apps import; `diga` is what humans run from a terminal.

## Library target — `Sources/SwiftVoxAlta/`

Flat directory, no submodules. Each file owns one concern:

| File | Role |
|---|---|
| `VoxAltaVoiceProvider.swift` | The SwiftHablare `VoiceProvider` conformance. Final class, `@unchecked Sendable`. Public entry point for app integrators. |
| `VoxAltaProviderDescriptor.swift` | Static descriptor (id, displayName, supportsAPIKey) used to register the provider with SwiftHablare. |
| `VoxAltaModelManager.swift` | `public actor` owning Qwen3-TTS model lifecycle: download (via `Acervo.ensureComponentReady`), load (via `TTSModelUtils.loadModel`), cache, unload, and memory pre-flight. Also defines `Qwen3TTSModelRepo` (the 7-variant catalog) and registers `ComponentDescriptor`s with SwiftAcervo at module init. |
| `VoxAltaVoiceCache.swift` | `public actor` keyed cache of resolved `Voice` objects — speeds up repeated `fetchVoices(...)` calls and protects shared cache state across concurrent provider calls. |
| `VoiceLock.swift` | `public struct` representing a "locked" voice: serialized clone prompt + reference text + design instruction + timestamp. The persistent voice ID. |
| `VoiceLockManager.swift` | `public enum` (namespace) of static methods that create / load / validate `VoiceLock`s. Loads a Base model, extracts a clone prompt from candidate audio, serializes, returns. Symmetric `loadVoiceLock` rehydrates one. |
| `GenerationContext.swift` | `public struct` envelope for per-generation metadata — text + optional structured metadata bag (`AnyCodableValue` map). Threaded through `VoiceLockManager` so call sites can attach context without changing every signature. |
| `GenerationSettings.swift` | `public struct` of TTS sampling knobs — temperature, topP, repetitionPenalty, maxTokens. Codable + Sendable; lives in `.vox` archives. |
| `VoxAltaConfig.swift` | `public struct` for one-shot config (output format, etc.) plus the `AudioOutputFormat` enum (WAV/AIFF/M4A). |
| `VoxAltaError.swift` | `public enum VoxAltaError: Error, LocalizedError` — every public throwing API funnels its failures through this type. |
| `VoxImporter.swift` / `VoxExporter.swift` | `public enum` namespaces that read and write `.vox` archives via the `VoxFormat` package. `.vox` is the portable voice-identity container (manifest + reference audio + clone prompt). |
| `AudioConversion.swift` | `public enum` namespace that converts between `MLXArray` (mlx-audio output) and WAV `Data`. NaN-guarded. |
| `AppleSiliconInfo.swift` | `public enum AppleSiliconGeneration` — wraps `Tuberia.DeviceCapability` to surface chip generation, neural-accelerator availability, total memory. Read at `loadModel` time to log Neural Accelerator detection on M5+. |

## Executable target — `Sources/diga/`

`diga` is a small CLI that lights up the library from a terminal — TTS smoke tests, voice cloning, voice management, ad-hoc rendering. It does **not** re-implement TTS; it consumes `VoxAltaModelManager` and `VoiceLockManager`.

| File | Role |
|---|---|
| `DigaCommand.swift` | Argument-parser entry point (`@main`). Routes flags into `DigaEngine`. |
| `DigaEngine.swift` | `actor DigaEngine` — orchestrates the synthesis loop: chunk text, call the library, concatenate WAV segments. Defines `WAVConcatenator` for stitching consecutive WAVs. |
| `BuiltinVoices.swift` | The 9 built-in CustomVoice preset speakers (no model load required to enumerate). |
| `VoiceStore.swift` | Persistent JSON-backed store for user-imported `.vox` voices under `~/.diga/voices/`. |
| `TextChunker.swift` | Sentence-boundary chunking via `NLTokenizer` so long inputs render in passes the model can hold. |
| `AudioFileWriter.swift` | Writes synthesized audio to WAV / AIFF / M4A via AVFoundation. |
| `AudioPlayback.swift` | WAV header parsing + playback through `AVAudioEngine`. |
| `Version.swift` | `enum DigaVersion { static let current }` — bumped during the release flow. |

`Sources/diga/` does **not** import `SwiftAcervo` directly — all model lifecycle calls go through `VoxAltaModelManager`. That single chokepoint is what keeps the audit surface small.

## External dependencies

```
SwiftVoxAlta (library)
├──▶ SwiftHablare         VoiceProvider protocol — what app integrators consume
├──▶ SwiftAcervo          Component Registry, model cache, App Group container
├──▶ Tuberia              MemoryManager, DeviceCapability (no TuberíaCatalog — diffusion-only)
├──▶ mlx-audio-swift      Qwen3-TTS inference (MLXAudioTTS module)
├──▶ vox-format           .vox archive read/write
├──▶ MLX (transitive)     Tensor ops; speech tokenizer
└──▶ MLXLMCommon          KV-cache types shared with mlx-swift-lm

diga (executable)
└──▶ swift-argument-parser  CLI flag parsing (in addition to all the library deps)
```

`Package.swift` uses the **sibling dependency pattern** for in-house packages (`intrusive-memory/*`): when a sibling checkout exists at `../<name>`, SPM resolves to the local copy; in CI (or any tree without the sibling), it falls back to the pinned remote release. `Foundation` is imported for the `ProcessInfo`-based detection. See `Package.swift:5-19`.

## Concurrency

| Type | Concurrency primitive | Why |
|---|---|---|
| `VoxAltaModelManager` | `public actor` | Serializes model load/unload/cache. Called from any thread; only one in-flight load at a time. |
| `VoxAltaVoiceCache` | `public actor` | Protects the resolved-voice cache from concurrent `fetchVoices` calls. |
| `VoxAltaVoiceProvider` | `final class, @unchecked Sendable` | SwiftHablare's `VoiceProvider` requires class identity; provider state is read-only after init or routed through the manager actor. |
| `VoiceLockManager` | `public enum` (namespace) | Pure static functions; no shared mutable state. Each call loads its own model handle via the manager. |
| `DigaEngine` | `actor` | CLI-side orchestrator; protects the synthesis pipeline from re-entry. |

`SwiftAcervo`'s `AcervoManager` is itself an actor — same-model downloads serialize across the whole process for free.

## Synthesis path

```
text + voiceId
  ↓
VoxAltaVoiceProvider.generateAudio(text:voiceId:languageCode:)
  ↓
[voice resolution — VoiceStore lookup, .vox archive open, or built-in preset]
  ↓
VoxAltaModelManager.loadModel(repo:)
  ├─ Acervo.ensureComponentReady(componentId)        ← downloads + hydrates manifest
  ├─ MemoryManager.softCheck(requiredBytes)          ← Tuberia, headroom-adjusted
  └─ AcervoManager.shared.withComponentAccess { … }  ← validates files + checksums
        then TTSModelUtils.loadModel(modelRepo:)     ← mlx-audio-swift
  ↓
MLXAudioTTS Qwen3TTSModel.generate / .generateWithClonePrompt
  ↓
MLXArray (24 kHz float samples)
  ↓
AudioConversion.mlxArrayToWAVData
  ↓
WAV Data
```

Subsequent calls with the same `repo` short-circuit on the cached model handle. Switching repos triggers `unloadModel` (which also calls `MemoryManager.shared.clearGPUCache()` to release Metal buffers before the next load).

## Acervo Component Registration

All 7 Qwen3-TTS variants are registered as **bare** `ComponentDescriptor`s — no `files:`, no `estimatedSizeBytes:`. SwiftAcervo hydrates each one from the CDN manifest on first `ensureComponentReady` call, so the file list and total size are always whatever the published manifest says.

```swift
// In VoxAltaModelManager.swift, evaluated once at module init:
ComponentDescriptor(
    id: "qwen3-tts-base-1.7b",
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
    minimumMemoryBytes: 3_400_000_000        // VoxAlta policy, not model metadata
)
```

`minimumMemoryBytes` stays declared because it's a VoxAlta policy decision (used for the pre-flight memory check), not a property of the model on disk. The deprecated 4-bit variant additionally carries `metadata: ["deprecated": "true"]`.

See `ACERVO_AUDIT.md` for the audit trail and the one outstanding upstream-blocked TOCTOU consideration.

## Memory model

Memory budgeting routes through `Tuberia.MemoryManager`, not Mach VM directly:

- `loadModel` reads `descriptor.minimumMemoryBytes`, multiplies by `Qwen3TTSModelSize.headroomMultiplier` (1.5×) for KV caches + activations + speech tokenizer, and calls `MemoryManager.shared.softCheck(requiredBytes:)`. A failed soft check **logs a warning to stderr but does not throw** — macOS can reclaim from compressed/inactive/cached pages on demand.
- A separate `validateMemory(forModelSizeBytes:)` exists for callers that want a hard gate; it routes through `MemoryManager.shared.hardValidate(...)` and throws `VoxAltaError.insufficientMemory`.
- `unloadModel` calls `MemoryManager.shared.clearGPUCache()` to synchronize the Metal stream and release cached buffers — without this, swapping models can crash inside `AGX::ComputeContext` on stale command buffers.

## Testing

`SwiftVoxAltaTests` exercises the library — voice provider semantics, vox import/export, error paths, generation context shape, audio conversion, voice lock manager, and `ComponentDescriptor` registration. These tests rely on Metal shader compilation and run only when xcodebuild can compile MLX kernels (i.e. local dev, not CI hosted runners — see `Makefile` `test-unit` target).

`DigaTests` exercises the CLI surface — chunking, voice store, audio writers/playback, version + release plumbing, and end-to-end binary integration. The binary integration suite (`DigaBinaryIntegrationTests`) drives `./bin/diga` as a subprocess against the cached Qwen3-TTS model and validates WAV output. It is excluded from `make test-unit` (binary + model not provisioned on CI runners) and runs explicitly via `make test-integration`.

## What stays out of SwiftVoxAlta

These concerns are deliberate non-goals; if you find yourself reaching for them in code review, that's the signal to push the work to the right repo:

- **Screenplay parsing** → `SwiftCompartido` (Fountain → `GuionDocumentModel`)
- **Voice creation / casting / character analysis** → `SwiftEchada` (`echada cast`)
- **Persistence of generated audio** → `Produciesta` (SwiftData store)
- **LLM inference** → `SwiftBruja` (Qwen LLM via MLX)
- **Diffusion / image generation** → `SwiftTuberia` `Catalog` modules; not in this graph

A historical proposal called "Character Studio" used to live in `docs/CHARACTER-STUDIO.md`; that design moved to `SwiftEchada/docs/CHARACTER-STUDIO.md` on 2026-04-30 because it spans script parsing + LLM analysis + voice design — none of which belong in a TTS library.
