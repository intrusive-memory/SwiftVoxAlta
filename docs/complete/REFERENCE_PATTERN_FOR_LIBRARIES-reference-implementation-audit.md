# SwiftVoxAlta ComponentDescriptor Pattern — Reference for Other Libraries

**Date**: 2026-04-17  
**Audience**: mlx-audio-swift, SwiftBruja, SwiftProyecto teams  
**Purpose**: Use SwiftVoxAlta as the reference implementation for ComponentDescriptor registration

---

## Quick Start: Copy This Pattern

SwiftVoxAlta implements the **ideal ComponentDescriptor pattern**. If you need to register models with SwiftAcervo, follow these 4 steps:

### Step 1: Define Your Model Variants (Enumeration)

Create an enum mapping your HuggingFace model IDs to component IDs:

```swift
public enum YourModelRepo: String, CaseIterable, Sendable {
    case model1_7B = "org/model-1.7b-bf16"
    case model0_6B = "org/model-0.6b-bf16"
    
    /// Component ID for SwiftAcervo registry
    public var componentId: String {
        switch self {
        case .model1_7B: return "your-model-1.7b"
        case .model0_6B: return "your-model-0.6b"
        }
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .model1_7B: return "Model 1.7B (bf16)"
        case .model0_6B: return "Model 0.6B (bf16)"
        }
    }
}
```

### Step 2: Declare Required Files

List **all** files your model needs (no dynamic discovery):

```swift
private let yourModelRequiredFiles: [ComponentFile] = [
    ComponentFile(relativePath: "config.json"),
    ComponentFile(relativePath: "model.safetensors"),
    ComponentFile(relativePath: "model.safetensors.index.json"),
    ComponentFile(relativePath: "tokenizer.json"),
    // ... add all files needed
]
```

### Step 3: Create ComponentDescriptors (Module-Level)

Define all descriptors statically and register them at module init:

```swift
private let yourModelComponentDescriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
        id: YourModelRepo.model1_7B.componentId,
        type: .languageModel,
        displayName: YourModelRepo.model1_7B.displayName,
        repoId: YourModelRepo.model1_7B.rawValue,
        files: yourModelRequiredFiles,
        estimatedSizeBytes: 3_400_000_000,
        minimumMemoryBytes: 3_400_000_000
    ),
    ComponentDescriptor(
        id: YourModelRepo.model0_6B.componentId,
        type: .languageModel,
        displayName: YourModelRepo.model0_6B.displayName,
        repoId: YourModelRepo.model0_6B.rawValue,
        files: yourModelRequiredFiles,
        estimatedSizeBytes: 1_200_000_000,
        minimumMemoryBytes: 1_200_000_000
    ),
]

// Lazy initializer — executed once on first module access
private let _registerYourModelComponents: Void = {
    Acervo.register(yourModelComponentDescriptors)
}()
```

### Step 4: Call ensureComponentReady() Before Loading

In your model manager, ensure files are downloaded before loading:

```swift
func loadModel(repo: String) async throws -> any YourModelType {
    // 1. Register components (if not already done)
    _ = _registerYourModelComponents
    
    // 2. Resolve component ID from repo
    guard let modelRepo = YourModelRepo(rawValue: repo) else {
        throw YourError.invalidModel(repo)
    }
    
    // 3. Ensure all files downloaded via SwiftAcervo
    try await Acervo.ensureComponentReady(modelRepo.componentId)
    
    // 4. Now load the model from the guaranteed path
    let model = try await yourLoader.loadModel(modelRepo: repo)
    return model
}
```

---

## Why This Pattern?

### Benefits of ComponentDescriptor registration:

| Benefit | Example |
|---------|---------|
| **Atomic downloads** | All files downloaded before model loading, no partial states |
| **Shared cache** | Models cached in `~/Library/SharedModels/` for cross-tool access |
| **Memory planning** | Can check available memory before loading (via `descriptor.minimumMemoryBytes`) |
| **Progress reporting** | SwiftAcervo tracks file-level progress automatically |
| **Error handling** | Type-safe error conversion (AcervoError → your error type) |
| **Backward compatibility** | Deprecated variants can be retained for migration |
| **Test coverage** | Use `CaseIterable` to test all variants automatically |

### Without this pattern (❌ DO NOT):

- Models downloaded on-demand by individual loaders (non-atomic)
- Cache paths vary by tool (duplicate downloads, disk waste)
- No memory pre-check (crashes possible)
- Error handling scattered across codebase
- Hard to deprecate old models

---

## SwiftVoxAlta Reference Code

### Key Files to Study

1. **ComponentDescriptor definitions**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` (lines 130–227)
   - Shows how to structure descriptors
   - Demonstrates lazy registration
   - Includes deprecated variant example

2. **Download workflow**: `VoxAltaModelManager.loadModel(repo:)` (lines 316–369)
   - Calls `ensureComponentReady()` (line 341)
   - Memory check using descriptor metadata (lines 332–336)
   - Error handling pattern (lines 349–351)

3. **Test coverage**: `Tests/SwiftVoxAltaTests/CDNAvailabilityTests.swift`
   - Iterates over all 7 models via `allCases`
   - Validates CDN availability
   - Tests manifest structure

---

## Common Patterns from VoxAlta

### Pattern 1: Lazy Module-Level Registration

**Why**: Ensures registration happens exactly once, before any model loading.

```swift
// Location: Module scope (not inside class or struct)
private let _registerComponents: Void = {
    Acervo.register(descriptors)
}()

// Location: Class/Actor init
public init() {
    _ = _registerComponents  // Triggers lazy evaluation
}
```

### Pattern 2: Enumeration for Type Safety

**Why**: Maps HuggingFace IDs to component IDs using Swift's type system.

```swift
// Prevents string errors at compile time
let componentId = Qwen3TTSModelRepo.base1_7B.componentId
// vs. error-prone: "qwen3-tts-base-1.7b"
```

### Pattern 3: Memory Headroom Multiplier

**Why**: Models need extra RAM for KV caches, activations, and intermediate tensors.

```swift
// VoxAlta uses 1.5x multiplier
let required = 3_400_000_000  // Model weights
let withHeadroom = UInt64(Double(required) * 1.5)  // With KV caches
```

### Pattern 4: Error Conversion at Boundaries

**Why**: Convert SwiftAcervo errors to library-specific errors at the boundary.

```swift
do {
    try await Acervo.ensureComponentReady(id)
} catch let error as AcervoError {
    switch error {
    case .downloadFailed:
        throw YourError.modelDownloadFailed
    default:
        throw YourError.modelNotAvailable
    }
}
```

---

## Testing Your Implementation

### 1. Unit Test: Verify Registration

```swift
func testComponentsRegistered() {
    let descriptor = Acervo.component("your-model-1.7b")
    XCTAssertNotNil(descriptor, "Component should be registered")
    XCTAssertEqual(descriptor?.displayName, "Your Model 1.7B")
    XCTAssertEqual(descriptor?.files.count, 4)  // Adjust to your count
}
```

### 2. Integration Test: Verify Download

```swift
func testModelDownloadsViaAcervo() async throws {
    // Download a small model or single file
    try await Acervo.ensureComponentReady("your-model-0.6b")
    
    // Verify it's cached
    XCTAssertTrue(Acervo.isModelAvailable("your-model-0.6b"))
}
```

### 3. Cross-Library Test: Verify Sharing

```swift
func testModelSharedWithOtherLibrary() async throws {
    // Your library downloads model
    try await Acervo.ensureComponentReady("your-model-1.7b")
    
    // Another library can access it
    let path = Acervo.modelPath(for: "your-model-1.7b")
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
}
```

---

## Checklist: Am I Following the Pattern?

- [ ] Created enum mapping HuggingFace IDs → component IDs
- [ ] Used `CaseIterable` on enum (enables test iteration)
- [ ] Declared all required files explicitly in `ComponentFile` array
- [ ] Created `ComponentDescriptor` array upfront (not dynamically)
- [ ] Used lazy module-level initializer for registration
- [ ] Called `Acervo.register()` in the lazy initializer
- [ ] Called `ensureComponentReady()` before model loading
- [ ] Used `minimumMemoryBytes` from descriptor for memory checks
- [ ] Applied appropriate headroom multiplier to required memory
- [ ] Converted SwiftAcervo errors to library-specific errors
- [ ] Wrote tests iterating over all variants via `allCases`
- [ ] Documented deprecated variants with metadata flag

---

## Q&A: Common Questions

### Q: Do I need to use SwiftAcervo?

**A**: Only if you want:
- Shared model cache across tools (saves disk space)
- Atomic downloads (no partial states)
- Memory pre-checks
- Test coverage for all model variants

If none of these matter, you can skip it. But we recommend using it.

### Q: How do I handle different quantization variants?

**A**: Register each separately with different component IDs:
- `qwen3-tts-base-1.7b` (bf16)
- `qwen3-tts-base-1.7b-8bit` (8-bit quantized)
- `qwen3-tts-base-1.7b-4bit` (4-bit quantized, deprecated)

Each has its own descriptor with different `minimumMemoryBytes`.

### Q: Can I download files progressively?

**A**: Not in the current pattern. `ensureComponentReady()` is atomic — all files must be downloaded before it returns. If you need progressive download, file a feature request with SwiftAcervo.

### Q: What if my model has dynamic files?

**A**: Don't do this. Declare all files upfront. If your model needs different files based on runtime config, you need to reorganize it into separate component descriptors (like VoxAlta's Base vs. CustomVoice variants).

### Q: How do I deprecate a model?

**A**: Keep it registered but add metadata:
```swift
ComponentDescriptor(
    id: "old-model",
    // ... other fields
    metadata: ["deprecated": "true"]
)
```

Apps can check this flag and either skip the model in UI or show a deprecation warning.

---

---

## Library-Specific Examples

### SwiftBruja (Witch) — Image Models

**Use case**: Register vision/image models from HuggingFace.

```swift
// Sources/SwiftBruja/ModelManager.swift

public enum BrujaVisionModelRepo: String, CaseIterable, Sendable {
    case clipBase = "openai/clip-vit-base-patch32"
    case clipLarge = "openai/clip-vit-large-patch14"
    
    public var componentId: String {
        switch self {
        case .clipBase: return "bruja-clip-vit-base"
        case .clipLarge: return "bruja-clip-vit-large"
        }
    }
    
    public var displayName: String {
        switch self {
        case .clipBase: return "CLIP ViT-Base"
        case .clipLarge: return "CLIP ViT-Large"
        }
    }
}

// Define required files
private let brujaVisionRequiredFiles: [ComponentFile] = [
    ComponentFile(relativePath: "config.json"),
    ComponentFile(relativePath: "model.safetensors"),
    ComponentFile(relativePath: "preprocessor_config.json"),
    ComponentFile(relativePath: "tokenizer.json"),
]

// Create descriptors
private let brujaVisionComponentDescriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
        id: BrujaVisionModelRepo.clipBase.componentId,
        type: .languageModel,
        displayName: BrujaVisionModelRepo.clipBase.displayName,
        repoId: BrujaVisionModelRepo.clipBase.rawValue,
        files: brujaVisionRequiredFiles,
        estimatedSizeBytes: 340_000_000,
        minimumMemoryBytes: 680_000_000  // 2x multiplier for inference
    ),
    ComponentDescriptor(
        id: BrujaVisionModelRepo.clipLarge.componentId,
        type: .languageModel,
        displayName: BrujaVisionModelRepo.clipLarge.displayName,
        repoId: BrujaVisionModelRepo.clipLarge.rawValue,
        files: brujaVisionRequiredFiles,
        estimatedSizeBytes: 1_210_000_000,
        minimumMemoryBytes: 2_420_000_000  // 2x multiplier
    ),
]

// Register at module init
private let _registerBrujaVisionComponents: Void = {
    Acervo.register(brujaVisionComponentDescriptors)
}()

// In BrujaModelManager.init()
public init() {
    _ = _registerBrujaVisionComponents
}

// In loadModel(repo:)
public func loadImage(modelRepo: BrujaVisionModelRepo) async throws -> BrujaImageProcessor {
    guard let descriptor = Acervo.component(modelRepo.componentId) else {
        throw BrujaError.modelNotRegistered(modelRepo.componentId)
    }
    
    try await Acervo.ensureComponentReady(modelRepo.componentId)
    
    // Now load from guaranteed path
    return try await loadImageModel(from: modelRepo.rawValue)
}
```

---

### SwiftProyecto (Project) — LLM Models

**Use case**: Register language models for script generation.

```swift
// Sources/SwiftProyecto/ModelManager.swift

public enum ProyectoLLMModelRepo: String, CaseIterable, Sendable {
    case llama3_8B = "meta-llama/Llama-3-8b"
    case llama3_70B = "meta-llama/Llama-3-70b"
    case mistral7B = "mistralai/Mistral-7B-v0.1"
    
    public var componentId: String {
        switch self {
        case .llama3_8B: return "proyeto-llama3-8b"
        case .llama3_70B: return "proyeto-llama3-70b"
        case .mistral7B: return "proyeto-mistral-7b"
        }
    }
    
    public var displayName: String {
        switch self {
        case .llama3_8B: return "Llama 3 8B"
        case .llama3_70B: return "Llama 3 70B"
        case .mistral7B: return "Mistral 7B"
        }
    }
}

// Define required files
private let proyectoLLMRequiredFiles: [ComponentFile] = [
    ComponentFile(relativePath: "config.json"),
    ComponentFile(relativePath: "generation_config.json"),
    ComponentFile(relativePath: "model.safetensors"),
    ComponentFile(relativePath: "model.safetensors.index.json"),
    ComponentFile(relativePath: "tokenizer.json"),
    ComponentFile(relativePath: "tokenizer_config.json"),
    ComponentFile(relativePath: "special_tokens_map.json"),
]

// Create descriptors
private let proyectoLLMComponentDescriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
        id: ProyectoLLMModelRepo.llama3_8B.componentId,
        type: .languageModel,
        displayName: ProyectoLLMModelRepo.llama3_8B.displayName,
        repoId: ProyectoLLMModelRepo.llama3_8B.rawValue,
        files: proyectoLLMRequiredFiles,
        estimatedSizeBytes: 15_000_000_000,
        minimumMemoryBytes: 22_500_000_000  // 1.5x multiplier
    ),
    ComponentDescriptor(
        id: ProyectoLLMModelRepo.llama3_70B.componentId,
        type: .languageModel,
        displayName: ProyectoLLMModelRepo.llama3_70B.displayName,
        repoId: ProyectoLLMModelRepo.llama3_70B.rawValue,
        files: proyectoLLMRequiredFiles,
        estimatedSizeBytes: 140_000_000_000,
        minimumMemoryBytes: 210_000_000_000  // 1.5x multiplier
    ),
    ComponentDescriptor(
        id: ProyectoLLMModelRepo.mistral7B.componentId,
        type: .languageModel,
        displayName: ProyectoLLMModelRepo.mistral7B.displayName,
        repoId: ProyectoLLMModelRepo.mistral7B.rawValue,
        files: proyectoLLMRequiredFiles,
        estimatedSizeBytes: 14_000_000_000,
        minimumMemoryBytes: 21_000_000_000  // 1.5x multiplier
    ),
]

// Register at module init
private let _registerProyectoLLMComponents: Void = {
    Acervo.register(proyectoLLMComponentDescriptors)
}()

// In ProyectoModelManager.init()
public init() {
    _ = _registerProyectoLLMComponents
}

// In loadModel(repo:)
public func loadLLM(modelRepo: ProyectoLLMModelRepo) async throws -> ProyectoLLMGenerator {
    // Ensure all files downloaded
    try await Acervo.ensureComponentReady(modelRepo.componentId)
    
    // Check available memory
    if let descriptor = Acervo.component(modelRepo.componentId) {
        await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
    }
    
    // Load model
    return try await loadLLMModel(from: modelRepo.rawValue)
}
```

---

### mlx-audio-swift (Audio Processing) — Speech Models

**Use case**: Register speech recognition and synthesis models.

```swift
// Sources/mlx-audio-swift/SpeechModelManager.swift

public enum MLXAudioSpeechModelRepo: String, CaseIterable, Sendable {
    case whisperBase = "openai/whisper-base"
    case whisperSmall = "openai/whisper-small"
    case seamlessM4T = "facebook/seamless-m4t-large"
    
    public var componentId: String {
        switch self {
        case .whisperBase: return "mlx-whisper-base"
        case .whisperSmall: return "mlx-whisper-small"
        case .seamlessM4T: return "mlx-seamless-m4t"
        }
    }
    
    public var displayName: String {
        switch self {
        case .whisperBase: return "Whisper Base"
        case .whisperSmall: return "Whisper Small"
        case .seamlessM4T: return "Seamless M4T"
        }
    }
}

// Define required files
private let mlxAudioRequiredFiles: [ComponentFile] = [
    ComponentFile(relativePath: "config.json"),
    ComponentFile(relativePath: "preprocessor_config.json"),
    ComponentFile(relativePath: "model.safetensors"),
    ComponentFile(relativePath: "model.safetensors.index.json"),
    ComponentFile(relativePath: "tokenizer.json"),
    ComponentFile(relativePath: "vocab.json"),
]

// Create descriptors
private let mlxAudioComponentDescriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
        id: MLXAudioSpeechModelRepo.whisperBase.componentId,
        type: .languageModel,
        displayName: MLXAudioSpeechModelRepo.whisperBase.displayName,
        repoId: MLXAudioSpeechModelRepo.whisperBase.rawValue,
        files: mlxAudioRequiredFiles,
        estimatedSizeBytes: 130_000_000,
        minimumMemoryBytes: 195_000_000  // 1.5x multiplier
    ),
    ComponentDescriptor(
        id: MLXAudioSpeechModelRepo.whisperSmall.componentId,
        type: .languageModel,
        displayName: MLXAudioSpeechModelRepo.whisperSmall.displayName,
        repoId: MLXAudioSpeechModelRepo.whisperSmall.rawValue,
        files: mlxAudioRequiredFiles,
        estimatedSizeBytes: 488_000_000,
        minimumMemoryBytes: 732_000_000  // 1.5x multiplier
    ),
    ComponentDescriptor(
        id: MLXAudioSpeechModelRepo.seamlessM4T.componentId,
        type: .languageModel,
        displayName: MLXAudioSpeechModelRepo.seamlessM4T.displayName,
        repoId: MLXAudioSpeechModelRepo.seamlessM4T.rawValue,
        files: mlxAudioRequiredFiles,
        estimatedSizeBytes: 2_300_000_000,
        minimumMemoryBytes: 3_450_000_000  // 1.5x multiplier
    ),
]

// Register at module init
private let _registerMLXAudioComponents: Void = {
    Acervo.register(mlxAudioComponentDescriptors)
}()

// In SpeechModelManager.init()
public init() {
    _ = _registerMLXAudioComponents
}

// In loadModel(repo:)
public func loadSpeechModel(modelRepo: MLXAudioSpeechModelRepo) async throws -> SpeechModel {
    // Ensure all files downloaded before proceeding
    try await Acervo.ensureComponentReady(modelRepo.componentId)
    
    // Load and return model
    return try await loadSpeechModelImpl(from: modelRepo.rawValue)
}
```

---

## Implementation Checklist

Use this checklist when implementing ComponentDescriptor registration in your library:

### Phase 1: Planning

- [ ] Identify all model variants you need to support
- [ ] Map each variant to a HuggingFace repo ID
- [ ] List all required files per model (no dynamic discovery)
- [ ] Estimate download size and minimum memory requirement
- [ ] Decide on headroom multiplier (VoxAlta uses 1.5x for TTS)

### Phase 2: Code Structure

- [ ] Create `YourModelRepo` enum with `CaseIterable`
- [ ] Add `componentId` computed property (returns snake_case ID)
- [ ] Add `displayName` computed property (returns user-friendly name)
- [ ] Define `yourModelRequiredFiles: [ComponentFile]` array
- [ ] Create `yourModelComponentDescriptors: [ComponentDescriptor]` array
- [ ] Create `_registerYourModelComponents` lazy initializer
- [ ] Call `_ = _registerYourModelComponents` in your manager's `init()`

### Phase 3: Download Workflow

- [ ] Import `import SwiftAcervo` at module top
- [ ] Call `Acervo.ensureComponentReady(modelRepo.componentId)` before loading
- [ ] Check memory via `Acervo.component().minimumMemoryBytes`
- [ ] Convert `AcervoError` to your library's error type
- [ ] Document error cases in public API

### Phase 4: Testing

- [ ] Write unit test: verify descriptors are registered (`Acervo.component()`)
- [ ] Write unit test: verify file counts match expectation
- [ ] Write unit test: verify memory metadata is set
- [ ] Write integration test: download a small model end-to-end
- [ ] Write cross-library test: verify model is shared in `~/Library/SharedModels/`
- [ ] Run tests with all variants via `CaseIterable`

### Phase 5: Documentation

- [ ] Add section to library README explaining model registration
- [ ] Link to this pattern guide in your CLAUDE.md
- [ ] Document how to add new models (update enum + descriptors)
- [ ] Document how to deprecate old models (add metadata flag)
- [ ] Include troubleshooting: common AcervoError cases

### Phase 6: Deprecation (Future)

- [ ] Keep old models registered with `metadata: ["deprecated": "true"]`
- [ ] Add migration guide in release notes
- [ ] Plan removal timeline (e.g., 2 versions later)

---

## Next Steps

1. **Copy VoxAlta's pattern** to your model manager using the library-specific examples above
2. **Run the implementation checklist** to verify compliance
3. **Write tests** for all your model variants
4. **Test cross-library access** with another tool
5. **Update your documentation** to reference this pattern

---

**Contact**: See SwiftVoxAlta AGENTS.md for architecture details, or contact @stovak with questions.
