# SwiftVoxAlta — Architecture (Ecosystem Interface Reference)

**Companion to**: [`REQUIREMENTS.md`](REQUIREMENTS.md)
**Role in ecosystem**: Infrastructure consumer. Adopts Acervo v2 Component Registry, MemoryManager, and DeviceCapability. Does NOT use the diffusion pipeline.

---

## Dependency Position

```
SwiftVoxAlta
├──▶ SwiftTubería/Tubería         (infrastructure ONLY: MemoryManager, DeviceCapability)
├──▶ SwiftAcervo                  (direct: component registration + ensureComponentReady)
├──▶ mlx-audio-swift              (TTS inference engine — unchanged)
├──▶ SwiftHablare                 (VoiceProvider protocol — unchanged)
├──▶ vox-format                   (.vox container — unchanged)
└──▶ swift-argument-parser        (diga CLI — unchanged)
```

**Key**: VoxAlta imports `Tubería` but does NOT import `TuberíaCatalog`. No diffusion components.

---

## What Migrates vs What Stays

### Migrates to SwiftTubería/Acervo

| Current Code | Replacement | Source |
|---|---|---|
| Direct Mach VM queries | `MemoryManager.shared.availableMemory` | Tubería |
| `MemoryManager.shared.softCheck()` / `.hardValidate()` | Same (new API) | Tubería |
| `AppleSiliconInfo` enum | `DeviceCapability.current` | Tubería |
| `Acervo.download(modelId, files: [...])` | `Acervo.ensureComponentReady(componentId)` | Acervo v2 |
| Hardcoded file lists | `ComponentDescriptor.files` | Acervo v2 |
| Direct path construction | `withComponentAccess` | Acervo v2 |
| `MLX.GPU.Stream.synchronize()` + `clearCache()` | `MemoryManager.shared.clearGPUCache()` | Tubería |

### Stays in VoxAlta (Unchanged)

- `VoxAltaVoiceProvider` (SwiftHablare `VoiceProvider` conformance)
- TTS generation path: `Qwen3TTSModel.generate()` via mlx-audio-swift
- VoiceLock, VoiceLockManager, VoxAltaVoiceCache
- VoxImporter / VoxExporter
- GenerationSettings (temperature, topP, repetitionPenalty, maxTokens)
- GenerationContext (metadata envelope)
- Audio conversion (MLXArray ↔ WAV)
- Preset speaker routing
- diga CLI

---

## Acervo Component Registration

```swift
// At import time
Acervo.register([
    ComponentDescriptor(id: "qwen3-tts-base-1.7b",       type: .languageModel, ...),
    ComponentDescriptor(id: "qwen3-tts-base-0.6b",       type: .languageModel, ...),
    ComponentDescriptor(id: "qwen3-tts-custom-1.7b",     type: .languageModel, ...),
    ComponentDescriptor(id: "qwen3-tts-custom-0.6b",     type: .languageModel, ...),
    ComponentDescriptor(id: "qwen3-tts-voicedesign-1.7b", type: .languageModel, ...),
    ComponentDescriptor(id: "qwen3-tts-base-1.7b-8bit",  type: .languageModel,
                        metadata: ["deprecated": "true"], ...),
])
```

**ComponentType**: `.languageModel` — NOT `.backbone` (which is for diffusion models).

### Model Loading Pattern (After Migration)

```swift
// In VoxAltaModelManager
let descriptor = Acervo.component(componentId)!
try await Acervo.ensureComponentReady(componentId)
let model = try await TTSModelUtils.loadModel(repo: descriptor.huggingFaceRepo)
```

VoxAlta obtains the HuggingFace repo string from the descriptor and passes it to mlx-audio-swift. The TTS loading path inside mlx-audio-swift is unchanged.

---

## MemoryManager Integration

```swift
// In VoxAltaModelManager
func validateMemory(for modelId: String) async throws {
    let descriptor = Acervo.component(modelId)!
    let requiredBytes = UInt64(Double(descriptor.minimumMemoryBytes) * 1.5)  // VoxAlta headroom
    let canFit = await MemoryManager.shared.softCheck(requiredBytes: requiredBytes)
    if !canFit {
        try await MemoryManager.shared.hardValidate(requiredBytes: requiredBytes)
    }
}
```

**Headroom**: 1.5x applied by VoxAlta (for KV caches, activations, speech tokenizer). MemoryManager provides raw available memory.

---

## DeviceCapability Integration

| VoxAlta Currently Uses | Replaced By |
|---|---|
| `AppleSiliconInfo.current.generation` | `DeviceCapability.current.chipGeneration` |
| `AppleSiliconInfo.current.hasNeuralEngine` | `DeviceCapability.current.hasNeuralAccelerators` |
| `AppleSiliconInfo.current.totalMemory` | `DeviceCapability.current.totalMemoryGB` |

---

## TTS Generation Path (Unchanged)

```
text + voiceId
    → model selection (preset vs clone)
    → VoxAltaModelManager.ensureModelLoaded(componentId)
         ├── Acervo.ensureComponentReady(componentId)   ← NEW
         ├── MemoryManager.softCheck(requiredBytes)     ← NEW
         └── TTSModelUtils.loadModel(repo:)             ← UNCHANGED
    → Qwen3TTSModel.generate() or .generateWithClonePrompt()
    → MLXArray (float samples, 24kHz)
    → AudioConversion.mlxArrayToWAVData()
    → Data (WAV)
```

---

## Cross-Pipeline Memory Tracking

When both TTS and image models are loaded:

```
MemoryManager.shared tracks:
  ├── "pixart-dit" (from DiffusionPipeline) ─── 300 MB
  ├── "t5-xxl" (from DiffusionPipeline)    ─── 1.2 GB
  └── "qwen3-tts-1.7b" (from VoxAlta)      ─── 3.4 GB
  Total: 4.9 GB

App decides eviction priority. MemoryManager reports but doesn't auto-unload.
```
