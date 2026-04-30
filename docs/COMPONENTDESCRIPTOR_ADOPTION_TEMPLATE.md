# ComponentDescriptor Adoption Template

**Target Audience**: Engineers implementing the ComponentDescriptor pattern in SwiftBruja, mlx-audio-swift, SwiftProyecto, or other libraries

**Source Reference**: SwiftVoxAlta (`/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`)

**Duration**: ~2-3 hours (Phases 1-5)

---

## Overview

This template guides you through adopting the ComponentDescriptor registration pattern used by SwiftVoxAlta. By following these steps, your library will:

- Register all model variants with SwiftAcervo at module initialization
- Enable atomic downloads and cross-library model sharing
- Provide memory metadata for safe model loading
- Support deprecated variant migration
- Integrate seamlessly with SwiftAcervo's CDN and caching system

---

## Phase 1: Planning (30 minutes)

### Step 1.1: Identify Your Models

List all model variants your library supports. For each model, record:

**Template**:

| # | Model Name | HuggingFace Repo ID | Size (MB) | Memory (MB) | Status | Notes |
|---|---|---|---|---|---|---|
| 1 | | | | | Active/Deprecated | |
| 2 | | | | | Active/Deprecated | |

**SwiftVoxAlta Example**:

| # | Model Name | HuggingFace Repo ID | Size (MB) | Memory (MB) | Status | Notes |
|---|---|---|---|---|---|---|
| 1 | Qwen3-TTS Base 1.7B (bf16) | mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16 | 3,400 | 3,400 | Active | Primary model |
| 2 | Qwen3-TTS Base 0.6B (bf16) | mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16 | 1,200 | 1,200 | Active | Lightweight |
| 3 | Qwen3-TTS Base 1.7B (4-bit) | mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit | 850 | 850 | Deprecated | Migration pending |

### Step 1.2: List Required Files

For each model variant, determine what files must be present for successful loading. SwiftVoxAlta requires:

1. `config.json` — Model configuration
2. `generation_config.json` — Generation settings
3. `preprocessor_config.json` — Audio preprocessing
4. `tokenizer_config.json` — Tokenizer configuration
5. `vocab.json` — Vocabulary
6. `merges.txt` — BPE merge file
7. `model.safetensors` — Sharded model weights
8. `model.safetensors.index.json` — Weight index
9. `speech_tokenizer/config.json` — Speech tokenizer config
10. `speech_tokenizer/configuration.json` — Alternative config
11. `speech_tokenizer/model.safetensors` — Tokenizer weights
12. `speech_tokenizer/preprocessor_config.json` — Tokenizer preprocessing

**For your library**, list required files in the same format.

### Step 1.3: Compute Memory Requirements

Memory = Model Size × Headroom Multiplier

**SwiftVoxAlta uses 1.5x** because Qwen3-TTS requires:
- KV caches during inference
- Intermediate activation tensors
- Speech tokenizer memory overhead

**Determine your headroom multiplier** based on your models' requirements. Common values:
- **1.3x** - Minimal overhead (lightweight inference)
- **1.5x** - Standard overhead (like VoxAlta)
- **2.0x** - Heavy overhead (complex models with batch processing)

---

## Phase 2: Code Structure (1 hour)

### Step 2.1: Create Model Enumeration

Copy the pattern from SwiftVoxAlta. This enum provides type-safe access to model variants.

**Template**:

```swift
import Foundation

/// Known model repository identifiers on HuggingFace.
public enum YourModelRepo: String, CaseIterable, Sendable {
  case modelSmall = "org/model-small-1.0b"
  case modelLarge = "org/model-large-7.0b"
  
  /// Human-readable display name for the model variant.
  public var displayName: String {
    switch self {
    case .modelSmall: return "Your Model Small (1.0B)"
    case .modelLarge: return "Your Model Large (7.0B)"
    }
  }
  
  /// The Acervo component ID for this model variant.
  public var componentId: String {
    switch self {
    case .modelSmall: return "your-model-small-1.0b"
    case .modelLarge: return "your-model-large-7.0b"
    }
  }
}
```

**SwiftVoxAlta Example** (lines 17–88 of VoxAltaModelManager.swift):

```swift
public enum Qwen3TTSModelRepo: String, CaseIterable, Sendable {
  case voiceDesign1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
  case base1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
  case base0_6B = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
  // ... other variants
  
  public var displayName: String {
    switch self {
    case .voiceDesign1_7B: return "VoiceDesign 1.7B (bf16)"
    case .base1_7B: return "Base 1.7B (bf16)"
    // ... other variants
    }
  }
  
  public var componentId: String {
    switch self {
    case .base1_7B: return "qwen3-tts-base-1.7b"
    case .base0_6B: return "qwen3-tts-base-0.6b"
    // ... other variants
    }
  }
}
```

### Step 2.2: Declare Required Files

Create a static array of `ComponentFile` entries. All your models will share this array.

**Template**:

```swift
import SwiftAcervo

private let yourModelRequiredFiles: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "model.safetensors"),
  ComponentFile(relativePath: "model.safetensors.index.json"),
  // ... all other required files
]
```

**SwiftVoxAlta Example** (lines 130–143):

```swift
private let qwen3TTSRequiredFiles: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "generation_config.json"),
  ComponentFile(relativePath: "preprocessor_config.json"),
  ComponentFile(relativePath: "tokenizer_config.json"),
  ComponentFile(relativePath: "vocab.json"),
  ComponentFile(relativePath: "merges.txt"),
  ComponentFile(relativePath: "model.safetensors"),
  ComponentFile(relativePath: "model.safetensors.index.json"),
  ComponentFile(relativePath: "speech_tokenizer/config.json"),
  ComponentFile(relativePath: "speech_tokenizer/configuration.json"),
  ComponentFile(relativePath: "speech_tokenizer/model.safetensors"),
  ComponentFile(relativePath: "speech_tokenizer/preprocessor_config.json"),
]
```

### Step 2.3: Create ComponentDescriptor Array

Build an array of `ComponentDescriptor` instances, one per model variant.

**Template**:

```swift
private let yourModelComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: YourModelRepo.modelSmall.componentId,
    type: .languageModel,
    displayName: YourModelRepo.modelSmall.displayName,
    repoId: YourModelRepo.modelSmall.rawValue,
    files: yourModelRequiredFiles,
    estimatedSizeBytes: 500_000_000,        // 500 MB
    minimumMemoryBytes: 750_000_000         // 750 MB (1.5x multiplier)
  ),
  ComponentDescriptor(
    id: YourModelRepo.modelLarge.componentId,
    type: .languageModel,
    displayName: YourModelRepo.modelLarge.displayName,
    repoId: YourModelRepo.modelLarge.rawValue,
    files: yourModelRequiredFiles,
    estimatedSizeBytes: 3_500_000_000,      // 3.5 GB
    minimumMemoryBytes: 5_250_000_000       // 5.25 GB (1.5x multiplier)
  ),
  // Deprecated variant (optional)
  ComponentDescriptor(
    id: "your-model-old-legacy",
    type: .languageModel,
    displayName: "Your Model Legacy (Deprecated)",
    repoId: "org/model-legacy",
    files: yourModelRequiredFiles,
    estimatedSizeBytes: 250_000_000,
    minimumMemoryBytes: 375_000_000,
    metadata: ["deprecated": "true"]       // Mark for migration
  ),
]
```

**SwiftVoxAlta Example** (lines 149–217):

```swift
private let qwen3TTSComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 3_400_000_000,
    minimumMemoryBytes: 3_400_000_000
  ),
  // ... 6 more descriptors
]
```

### Step 2.4: Create Lazy Registration Initializer

Add a module-level lazy initializer that registers all descriptors with SwiftAcervo.

**Template**:

```swift
/// Module-level registration trigger.
///
/// This `let` is evaluated once (lazily) on first access, registering all
/// component descriptors with the SwiftAcervo Component Registry.
private let _registerYourModelComponents: Void = {
  Acervo.register(yourModelComponentDescriptors)
}()
```

**SwiftVoxAlta Example** (lines 225–227):

```swift
private let _registerQwen3TTSComponents: Void = {
  Acervo.register(qwen3TTSComponentDescriptors)
}()
```

### Step 2.5: Trigger Registration in Manager Init

Modify your manager class to reference the lazy initializer during initialization.

**Template**:

```swift
public class YourModelManager {
  public init() {
    // Trigger lazy registration of all component descriptors.
    _ = _registerYourModelComponents
  }
  
  // ... rest of manager code
}
```

**SwiftVoxAlta Example** (lines 269–272):

```swift
public actor VoxAltaModelManager {
  public init() {
    // Trigger lazy registration of all Qwen3-TTS ComponentDescriptors.
    _ = _registerQwen3TTSComponents
  }
  // ... rest of manager code
}
```

---

## Phase 3: Download Workflow Integration (30 minutes)

### Step 3.1: Call ensureComponentReady() Before Loading

Before loading a model, call `Acervo.ensureComponentReady()` with the component ID. This ensures all required files are present, downloading from CDN if necessary.

**Template**:

```swift
public func loadModel(repo: String) async throws {
  // Step 1: Map HuggingFace repo ID to component ID
  if let modelRepo = YourModelRepo(rawValue: repo) {
    // Step 2: Ensure all files are present (download if needed)
    try await Acervo.ensureComponentReady(modelRepo.componentId)
  }
  
  // Step 3: Load model from guaranteed path
  let modelPath = Acervo.modelPath(for: modelRepo.componentId)
  let model = try loadModelFromDisk(at: modelPath)
  
  return model
}
```

**SwiftVoxAlta Example** (lines 340–342):

```swift
if let modelRepo = Qwen3TTSModelRepo(rawValue: repo) {
    try await Acervo.ensureComponentReady(modelRepo.componentId)
}
```

### Step 3.2: Implement Memory Checking

Use the descriptor's `minimumMemoryBytes` to check if sufficient memory is available before loading.

**Template**:

```swift
public func loadModel(repo: String) async throws {
  // Step 1: Get descriptor for memory check
  if let modelRepo = YourModelRepo(rawValue: repo),
      let descriptor = Acervo.component(modelRepo.componentId) {
    // Step 2: Check available memory
    let requiredBytes = UInt64(descriptor.minimumMemoryBytes)
    try await checkMemory(forModelSizeBytes: Int(requiredBytes))
  }
  
  // ... proceed with download and loading
}

private func checkMemory(forModelSizeBytes sizeBytes: Int) async throws {
  let availableMemory = await MemoryManager.shared.availableMemory()
  if availableMemory < UInt64(sizeBytes) {
    throw YourError.insufficientMemory(
      "Need \(sizeBytes) bytes, but only \(availableMemory) available"
    )
  }
}
```

**SwiftVoxAlta Example** (lines 332–336):

```swift
if let modelRepo = Qwen3TTSModelRepo(rawValue: repo),
    let descriptor = Acervo.component(modelRepo.componentId) {
  await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
}
```

### Step 3.3: Convert Acervo Errors to Library-Specific Errors

At your library's public boundary, catch `AcervoError` and convert to your own error type.

**Template**:

```swift
public func loadModel(repo: String) async throws {
  do {
    try await Acervo.ensureComponentReady(modelRepo.componentId)
  } catch let error as AcervoError {
    throw YourError.modelNotAvailable(
      "Failed to download model '\(repo)': \(error.localizedDescription)"
    )
  } catch {
    throw YourError.modelNotAvailable(
      "Failed to load model: \(error.localizedDescription)"
    )
  }
}
```

**SwiftVoxAlta Example** (lines 345–352):

```swift
do {
  model = try await TTSModelUtils.loadModel(modelRepo: repo)
} catch {
  throw VoxAltaError.modelNotAvailable(
    "Failed to load model from '\(repo)': \(error.localizedDescription)"
  )
}
```

---

## Phase 4: Testing (45 minutes)

### Step 4.1: Unit Test - Verify Registration

Test that all descriptors are registered at initialization.

**Template**:

```swift
import XCTest
import SwiftAcervo

class YourModelComponentTests: XCTestCase {
  func testAllModelsRegistered() {
    // Create an instance to trigger registration
    let manager = YourModelManager()
    
    // Verify each model is registered
    for modelRepo in YourModelRepo.allCases {
      let descriptor = Acervo.component(modelRepo.componentId)
      XCTAssertNotNil(descriptor, "Model \(modelRepo.rawValue) should be registered")
    }
  }
  
  func testDescriptorMetadata() {
    let manager = YourModelManager()
    
    for modelRepo in YourModelRepo.allCases {
      let descriptor = Acervo.component(modelRepo.componentId)!
      XCTAssertEqual(descriptor.id, modelRepo.componentId)
      XCTAssertEqual(descriptor.displayName, modelRepo.displayName)
      XCTAssertGreater(descriptor.estimatedSizeBytes, 0)
      XCTAssertGreater(descriptor.minimumMemoryBytes, 0)
    }
  }
}
```

### Step 4.2: Unit Test - Verify File Counts

Test that each descriptor declares all required files.

**Template**:

```swift
func testRequiredFilesPresent() {
  let manager = YourModelManager()
  let expectedFileCount = 12  // Adjust based on your models
  
  for modelRepo in YourModelRepo.allCases {
    let descriptor = Acervo.component(modelRepo.componentId)!
    XCTAssertEqual(
      descriptor.files.count,
      expectedFileCount,
      "Model \(modelRepo.displayName) should declare \(expectedFileCount) files"
    )
  }
}
```

### Step 4.3: Integration Test - Download and Load

Test end-to-end download and loading (using smallest model for speed).

**Template**:

```swift
func testModelDownloadAndLoad() async throws {
  let manager = YourModelManager()
  
  // Use smallest model to speed up test
  let repo = YourModelRepo.modelSmall.rawValue
  
  // This should download and cache the model
  let model = try await manager.loadModel(repo: repo)
  
  // Verify model loaded successfully
  XCTAssertNotNil(model)
}
```

### Step 4.4: Cross-Library Test (Optional)

If another library is also using ComponentDescriptor, test shared model access.

**Template**:

```swift
func testSharedModelAccess() async throws {
  let manager1 = YourModelManager()
  let manager2 = AnotherLibraryModelManager()
  
  // Load via first manager
  let model1 = try await manager1.loadModel(repo: "org/shared-model")
  
  // Access via second manager (should use cached version)
  let path = Acervo.modelPath(for: "shared-model-id")
  XCTAssertNotNil(path, "Model should be accessible via shared path")
}
```

---

## Phase 5: Documentation (15 minutes)

### Step 5.1: Update README

Add a "Model Registration" section to your README explaining the ComponentDescriptor pattern.

**Template**:

```markdown
## Model Registration

This library registers all supported models with SwiftAcervo at initialization. 
When you create a `YourModelManager` instance, all models are automatically 
registered with the Component Registry, enabling atomic downloads and cross-library sharing.

### Supported Models

- **Your Model Small (1.0B)**: Lightweight, fast inference
- **Your Model Large (7.0B)**: Higher quality, more memory required

### Memory Requirements

Memory usage = Model Size × 1.5× (for caches and activations)

- Small model: ~750 MB RAM required
- Large model: ~5.25 GB RAM required

### How It Works

1. **Registration**: All models registered when `YourModelManager` is initialized
2. **Download**: Call `loadModel(repo:)` to download (first time) and load model
3. **Caching**: Downloaded models cached via SwiftAcervo (path resolved at runtime by `Acervo.sharedModelsDirectory` — never assume a specific location)
4. **Sharing**: Other tools can access cached models via Acervo API

See the [ComponentDescriptor Pattern Guide](../docs/COMPONENTDESCRIPTOR_ADOPTION_TEMPLATE.md) 
for implementation details.
```

### Step 5.2: Link to Pattern Documentation

Add a link in your README pointing to this adoption template.

**Template**:

```markdown
## Implementation Reference

For details on the ComponentDescriptor pattern, see:
- [SwiftVoxAlta Audit Report](../docs/SWIFTVOXALTA_AUDIT_REPORT.md)
- [ComponentDescriptor Adoption Guide](../docs/COMPONENTDESCRIPTOR_ADOPTION_TEMPLATE.md)
- [Quick Reference](../docs/COMPONENTDESCRIPTOR_QUICK_REFERENCE.md)
```

### Step 5.3: Document Deprecation Process

If you have deprecated models, document the migration path.

**Template**:

```markdown
## Deprecated Models

The following models are deprecated and will be removed in a future release:

- **Your Model Legacy**: Use "Your Model Small" instead

Existing cached copies will continue to work, but new downloads are not recommended.
To clean up deprecated models, delete the corresponding subdirectory from
`Acervo.sharedModelsDirectory` (resolve at runtime — do not hardcode the path).
```

---

## Verification Checklist

Before considering implementation complete, verify:

- [ ] Model enumeration defined with `CaseIterable` and `Sendable`
- [ ] Component ID mapping implemented in enum extension
- [ ] Required files declared in `ComponentFile` array
- [ ] All models have `ComponentDescriptor` instances
- [ ] Lazy initializer created and referenced in manager init
- [ ] `Acervo.ensureComponentReady()` called before loading
- [ ] Memory checking implemented using descriptor metadata
- [ ] Error conversion from AcervoError to library error working
- [ ] Unit tests verify registration and metadata
- [ ] Integration test covers download and loading
- [ ] README updated with model information
- [ ] Deprecated variants marked with metadata flag (if applicable)

---

## Common Issues & Solutions

### Issue: Models not found after registration

**Cause**: Registration might not have been triggered yet.

**Solution**: Ensure your manager's `init()` method references `_registerYourModelComponents`:

```swift
public init() {
  _ = _registerYourModelComponents  // This must be here!
}
```

### Issue: Memory check always fails

**Cause**: Headroom multiplier too aggressive or memory estimate incorrect.

**Solution**: Reduce headroom multiplier (from 1.5 to 1.3) or verify model size estimates:

```swift
let actualSize = FileManager.default.attributesOfItem(
  atPath: modelPath
)["NSFileSize"] as! Int
```

### Issue: Deprecated models still appear in UI

**Cause**: Metadata flag not being checked.

**Solution**: Filter out deprecated models in your UI layer:

```swift
let activeModels = YourModelRepo.allCases.filter { repo in
  let descriptor = Acervo.component(repo.componentId)
  return descriptor?.metadata?["deprecated"] != "true"
}
```

### Issue: Download fails with "File not found"

**Cause**: Required files list incomplete.

**Solution**: Verify all files are present on HuggingFace repo:

```bash
huggingface-cli repo ls <repo-id> | grep -E "config|model|tokenizer"
```

---

## Next Steps

1. **Complete all 5 phases** using this template
2. **Run verification checklist** to ensure completeness
3. **Submit PR** with new ComponentDescriptor registration
4. **Link to this guide** in PR description
5. **Share findings** in project documentation (README, AGENTS.md)

For questions, refer to:
- **SwiftVoxAlta source**: `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`
- **Audit report**: `/Users/stovak/Projects/SwiftVoxAlta/docs/SWIFTVOXALTA_AUDIT_REPORT.md`
- **Quick reference**: `/Users/stovak/Projects/SwiftVoxAlta/docs/COMPONENTDESCRIPTOR_QUICK_REFERENCE.md`

---

**Template Version**: 1.0  
**Last Updated**: 2026-04-18  
**Reference Implementation**: SwiftVoxAlta (Sortie 1.1)
