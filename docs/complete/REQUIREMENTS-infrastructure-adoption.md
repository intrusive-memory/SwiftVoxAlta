# SwiftVoxAlta — Requirements (SwiftTubería Integration)

**Status**: DRAFT — debate and refine before implementation.
**Parent project**: [`PROJECT_PIPELINE.md`](../PROJECT_PIPELINE.md) — Unified MLX Inference Architecture (§4. SwiftVoxAlta, Wave 4.3–4.5)
**Scope**: How SwiftVoxAlta adopts SwiftTubería's infrastructure services while preserving its VoiceProvider interface and TTS-specific pipeline.

---

## Motivation

SwiftVoxAlta is a TTS voice synthesis library implementing SwiftHablare's `VoiceProvider` protocol. It uses mlx-audio-swift for Qwen3-TTS inference. Unlike the image generation libraries, VoxAlta's core inference pipeline (autoregressive text → audio token generation) is fundamentally different from the diffusion pipeline — it does not use schedulers, latent denoising, or VAE decoding.

However, VoxAlta shares significant infrastructure with the image models:
- Model downloading and caching (currently via SwiftAcervo)
- Memory management and device capability detection
- Weight loading and quantization patterns
- Apple Silicon generation detection

SwiftTubería integration for VoxAlta is **infrastructure adoption, not pipeline migration**. The TTS generation path remains in mlx-audio-swift. What changes is the plumbing underneath: model management, memory budgeting, and device detection move to the shared pipeline infrastructure.

### What Changes vs What Stays

| Concern | Changes (→ SwiftTubería) | Stays In VoxAlta |
|---|---|---|
| Model downloading + caching | **Migrates** — unified ModelRegistry replaces direct Acervo usage | — |
| Memory management + validation | **Migrates** — MemoryManager replaces VoxAltaModelManager memory checks | — |
| Device capability detection | **Migrates** — replaces AppleSiliconInfo | — |
| VoiceProvider protocol impl | — | **Stays** |
| Voice clone prompt handling | — | **Stays** |
| VoiceLockManager | — | **Stays** |
| VoxAltaVoiceCache (2-layer) | — | **Stays** |
| .vox file import/export | — | **Stays** |
| GenerationSettings (sampling) | — | **Stays** |
| GenerationContext (metadata) | — | **Stays** |
| Audio conversion (MLXArray ↔ WAV) | — | **Stays** |
| Preset speaker routing | — | **Stays** |
| diga CLI | — | **Stays** |

---

## V1. Infrastructure Adoption

### V1.1 Acervo Component Registration

**Current**: `VoxAltaModelManager` handles model loading via `TTSModelUtils.loadModel()` from mlx-audio-swift, with Acervo v1 for caching (caller-specified file lists).

**Target**: Register Qwen3-TTS model variants as `ComponentDescriptor` entries in SwiftAcervo's Component Registry:

| Component | Acervo ID | Type | Size |
|---|---|---|---|
| Qwen3-TTS Base 1.7B | `qwen3-tts-base-1.7b` | languageModel | ~3.4 GB |
| Qwen3-TTS Base 0.6B | `qwen3-tts-base-0.6b` | languageModel | ~1.2 GB |
| Qwen3-TTS CustomVoice 1.7B | `qwen3-tts-custom-1.7b` | languageModel | ~3.4 GB |
| Qwen3-TTS CustomVoice 0.6B | `qwen3-tts-custom-0.6b` | languageModel | ~1.2 GB |
| Qwen3-TTS VoiceDesign 1.7B | `qwen3-tts-voicedesign-1.7b` | languageModel | ~3.4 GB |
| Qwen3-TTS Base 1.7B 8bit | `qwen3-tts-base-1.7b-8bit` | languageModel | ~1.7 GB |

Each descriptor declares its HuggingFace repo, required files, expected sizes, and SHA-256 checksums. Downloads use `Acervo.ensureComponentReady(id)` instead of manually specifying file lists. Model access uses `AcervoManager.shared.withComponentAccess(id)` — no file paths in VoxAlta code.

**File discovery integration**: No changes to mlx-audio-swift. VoxAlta obtains the repo string from `ComponentDescriptor.huggingFaceRepo` and passes it to `TTSModelUtils.loadModel(repo:)` unchanged:
```swift
let descriptor = Acervo.component(componentId)!
try await Acervo.ensureComponentReady(componentId)
let model = try await TTSModelUtils.loadModel(repo: descriptor.huggingFaceRepo)
```

**4-bit model deprecation**: 4-bit variants are registered with `metadata["deprecated": "true"]`. Keep Acervo registration (models may still be on disk), but exclude from UI/CLI model selection by default. diga CLI shows 4-bit only with `--include-deprecated` flag. Produciesta never shows deprecated variants in the model picker.

**Benefit**: Unified download status, cache management, and disk usage tracking across all MLX models (image + audio). A user can see "you have 8 GB of models cached" across the entire ecosystem.

### V1.2 Memory Manager

**Current**: `VoxAltaModelManager` queries Mach VM stats directly, applies `headroomMultiplier = 1.5`, provides `checkMemory()` (soft) and `validateMemory()` (hard).

**Target**: Delegate to SwiftTubería's `MemoryManager`:
- Replace direct Mach VM queries with `MemoryManager.availableMemory`
- Replace `AppleSiliconInfo` with `MemoryManager.deviceCapability`
- Keep the soft/hard distinction — `MemoryManager` provides both warning and gating APIs
- **Headroom multiplier**: Per-consumer, not in MemoryManager. VoxAlta applies its 1.5× headroom (for KV caches, activations, speech tokenizer) before calling `MemoryManager.softCheck`/`hardValidate`. MemoryManager provides raw available memory; the multiplied value is what gets validated.
- `VoxAltaModelManager` becomes a thin wrapper that translates between VoxAlta's model loading semantics and the MemoryManager's budget system

**Example calling pattern**:
```swift
// In VoxAltaModelManager (actor)
func validateMemory(for modelId: String) async throws {
    let descriptor = Acervo.component(modelId)!
    let requiredBytes = UInt64(Double(descriptor.minimumMemoryBytes) * 1.5)  // 1.5× headroom
    let canFit = await MemoryManager.shared.softCheck(requiredBytes: requiredBytes)
    if !canFit {
        try await MemoryManager.shared.hardValidate(requiredBytes: requiredBytes)
        // throws PipelineError.insufficientMemory if truly insufficient
    }
}
```

### V1.3 Device Capability Detection

**Current**: `AppleSiliconInfo` enum detects M1–M5 variants, tracks Neural Engine availability.

**Target**: Replace `AppleSiliconInfo` with SwiftTubería's `DeviceCapability` (see SwiftTubería `requirements/INFRASTRUCTURE.md` § Device Capability Detection). `DeviceCapability.current` provides chip generation, memory, platform, and `hasNeuralAccelerators` — all the information VoxAlta currently derives from `AppleSiliconInfo`. SwiftTubería implements the Neural Accelerator detection based on the pattern from VoxAlta's existing `AppleSiliconInfo` (this is done in SwiftTubería Wave 1.3, before VoxAlta's Wave 4.3). VoxAlta only consumes the shared detection — no upstream code contribution needed.

### V1.4 GPU Cache Clearing

After adopting SwiftTubería's MemoryManager, VoxAlta should replace direct MLX GPU calls with the shared API:

| Current (VoxAlta) | Target (via MemoryManager) |
|---|---|
| `MLX.GPU.Stream.synchronize()` + `MLX.GPU.Memory.clearCache()` | `await MemoryManager.shared.clearGPUCache()` |

`MemoryManager.clearGPUCache()` performs the same MLX calls internally but also updates its loaded-component tracking. This ensures that when both TTS and image models share the same device, the MemoryManager has an accurate picture of GPU memory state. Direct MLX calls bypass this tracking and can lead to stale memory estimates.

---

## V2. What Does NOT Change

### V2.1 VoiceProvider Protocol

`VoxAltaVoiceProvider` continues to conform to SwiftHablare's `VoiceProvider` protocol. This is VoxAlta's public API contract and is completely independent of the pipeline architecture.

### V2.2 TTS Generation Path

The actual audio generation still flows through mlx-audio-swift:

```
text + voiceId
    → model selection (preset vs clone)
    → Qwen3TTSModel.generate() or .generateWithClonePrompt()
    → MLXArray (float samples, 24kHz)
    → AudioConversion.mlxArrayToWAVData()
    → Data (WAV)
```

SwiftTubería does not provide a TTS pipeline template — TTS is autoregressive, not diffusion-based. The generation path remains in mlx-audio-swift. VoxAlta continues to be the integration layer between SwiftHablare's voice abstraction and mlx-audio-swift's inference engine.

### V2.3 Voice Identity System

VoiceLock, VoiceLockManager, VoxAltaVoiceCache, VoxImporter, VoxExporter — all unchanged. These are domain-specific to voice synthesis and have no overlap with image/video generation.

### V2.4 GenerationSettings and GenerationContext

Sampling parameters (temperature, topP, repetitionPenalty, maxTokens) and the metadata envelope are TTS-specific. No changes.

---

## V3. Future: Non-Speech Audio Diffusion

When non-speech audio generation is added (music, sound effects via models like AudioLDM, Riffusion, etc.), that work would be a **separate model plugin** for SwiftTubería — not an extension of SwiftVoxAlta. Non-speech audio diffusion follows the standard diffusion pipeline pattern:

```
TextEncoder → AudioDiffusionBackbone → AudioVAEDecoder → AudioRenderer
```

This would be a new package (e.g., `audiocraft-swift-mlx` or similar) that provides its backbone and plugs into SwiftTubería's `DiffusionPipeline` with an `AudioRenderer` from the catalog. SwiftVoxAlta's TTS path and the diffusion audio path are architecturally independent.

---

## V4. Dependency Changes

**Current**:
```
SwiftVoxAlta
├── mlx-audio-swift (Qwen3-TTS inference)
├── SwiftHablare (VoiceProvider protocol)
├── SwiftAcervo (model caching)
├── vox-format (.vox container)
└── swift-argument-parser (CLI)
```

**Target**:
```
SwiftVoxAlta
├── mlx-audio-swift (Qwen3-TTS inference — unchanged)
├── SwiftHablare (VoiceProvider protocol — unchanged)
├── SwiftAcervo (v2 — Component Registry for model management)
├── SwiftTubería/Tubería (infrastructure only — MemoryManager, DeviceCapability)
├── vox-format (.vox container — unchanged)
└── swift-argument-parser (CLI — unchanged)
```

SwiftAcervo remains a direct dependency (upgraded to v2 with Component Registry). SwiftTubería provides only infrastructure services (MemoryManager, DeviceCapability). VoxAlta imports only the `Tubería` target (protocols + infrastructure), NOT `TuberíaCatalog` (diffusion components).

**Import scope**: VoxAlta imports `Tubería` solely for `MemoryManager` and `DeviceCapability`. The diffusion pipeline protocols (`TextEncoder`, `Backbone`, `Decoder`, etc.) are available in the `Tubería` module but are intentionally unused — TTS generation flows through mlx-audio-swift, not through `DiffusionPipeline`. This is by design: VoxAlta connects to the infrastructure (water meter and pressure regulator) without using the pipes.

---

## V5. Migration Path

1. **Phase 1 — Acervo v2 adoption**: Register TTS model variants as `ComponentDescriptor` entries in SwiftAcervo's Component Registry. Switch from `Acervo.download(modelId, files: [...])` to `Acervo.ensureComponentReady(componentId)`. Switch model access to `withComponentAccess` pattern.

2. **Phase 2 — Memory manager adoption**: Replace direct Mach VM queries and AppleSiliconInfo with SwiftTubería's MemoryManager and DeviceCapability. Contribute M5 Neural Accelerator detection upstream.

3. **Phase 3 — Cleanup**: Remove hardcoded file lists, HuggingFace repo strings, and direct path construction from VoxAltaModelManager. All model knowledge lives in the ComponentDescriptor declarations.

Throughout all phases, the VoiceProvider API, generation path, and voice identity system remain unchanged. External consumers (SwiftHablare, Produciesta) see no behavioral difference.

---

## V6. Testing Impact

### V6.1 Tests That Stay Unchanged
- VoiceProvider protocol conformance
- Voice cache operations
- VoiceLock creation and usage
- Audio conversion (MLXArray ↔ WAV)
- VoxImporter / VoxExporter
- GenerationContext and GenerationSettings
- CLI integration tests (diga)
- Error path tests

### V6.2 Tests That Change
- `VoxAltaModelManager` tests — update to verify delegation to Acervo Component Registry and MemoryManager
- `AppleSiliconInfo` tests — verify alignment with DeviceCapability (or remove if fully delegated)
- Memory validation tests — verify MemoryManager integration

### V6.3 New Tests
- Acervo Component Registry integration: verify TTS model entries are correctly registered and queryable via `Acervo.isComponentReady()` and `Acervo.registeredComponents()`
- Cross-pipeline memory coordination: verify that having a TTS model and an image model loaded simultaneously is correctly tracked by MemoryManager

### V6.4 Coverage and CI Stability Requirements

- All new code must achieve **≥90% line coverage** in unit tests. Coverage is measured per-target and enforced in CI.
- **No timed tests**: Tests must not use `sleep()`, `Task.sleep()`, `Thread.sleep()`, fixed-duration `XCTestExpectation` timeouts, or any wall-clock assertions. All asynchronous behavior must be validated via deterministic synchronization (`async`/`await`, `AsyncStream`, fulfilled expectations with immediate triggers).
- **No environment-dependent tests**: Unit tests for Acervo registration, MemoryManager delegation, and DeviceCapability integration must use injected/mock dependencies and run without real model weights, network access, or GPU. Tests requiring real TTS model inference are integration tests and must be clearly separated (separate test target or `#if INTEGRATION_TESTS` gate).
- **Flaky tests are test failures**: A test that passes intermittently is treated as a failing test until fixed. CI must not use retry-on-failure to mask flakiness.
