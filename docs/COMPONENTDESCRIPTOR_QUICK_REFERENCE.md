# ComponentDescriptor Quick Reference

**One-page guide** for developers implementing the ComponentDescriptor pattern.

**Reference**: SwiftVoxAlta (Production Implementation)  
**Print This**: Yes, fits on one page

---

## What is ComponentDescriptor?

A Swift pattern for registering machine learning models with SwiftAcervo, enabling:
- ✅ Atomic downloads (all files guaranteed present)
- ✅ Cross-library model sharing
- ✅ Memory metadata for safe loading
- ✅ Deprecation support

---

## Implementation Flow (5 Steps)

```
1. Enum          2. Files         3. Descriptors    4. Lazy Init      5. Load
┌──────────┐    ┌──────────┐     ┌──────────┐      ┌──────────┐      ┌──────┐
│YourModel ├──→ │Required  ├────→│Component ├─────→│_register├─────→│Manager
│Repo enum │    │Files[]   │     │Descriptor│      │Components┘      │init()
│          │    │          │     │array[]   │      │                 │
└──────────┘    └──────────┘     └──────────┘      └──────────┘      └──────┘
  (Type-safe)    (Explicit)      (Metadata)       (Thread-safe)     (Triggering)
```

---

## Code Template

### Step 1: Create Enumeration

```swift
public enum YourModelRepo: String, CaseIterable, Sendable {
  case small = "org/model-small-1.0b"
  case large = "org/model-large-7.0b"
  
  public var displayName: String {
    switch self {
    case .small: return "Small (1.0B)"
    case .large: return "Large (7.0B)"
    }
  }
  
  public var componentId: String {
    switch self {
    case .small: return "your-model-small-1.0b"
    case .large: return "your-model-large-7.0b"
    }
  }
}
```

### Step 2: Declare Files

```swift
private let yourModelRequiredFiles: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "model.safetensors"),
  ComponentFile(relativePath: "model.safetensors.index.json"),
  // ... all required files
]
```

### Step 3: Create Descriptors

```swift
private let yourModelComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: YourModelRepo.small.componentId,
    type: .languageModel,
    displayName: YourModelRepo.small.displayName,
    repoId: YourModelRepo.small.rawValue,
    files: yourModelRequiredFiles,
    estimatedSizeBytes: 500_000_000,      // 500 MB
    minimumMemoryBytes: 750_000_000       // 500 MB × 1.5
  ),
  // ... one per model variant
]
```

### Step 4: Lazy Registration

```swift
private let _registerYourModelComponents: Void = {
  Acervo.register(yourModelComponentDescriptors)
}()

public class YourManager {
  public init() {
    _ = _registerYourModelComponents
  }
}
```

### Step 5: Load Models

```swift
public func loadModel(repo: String) async throws {
  // Ensure files downloaded
  if let model = YourModelRepo(rawValue: repo) {
    try await Acervo.ensureComponentReady(model.componentId)
  }
  
  // Load from guaranteed path
  let path = Acervo.modelPath(for: YourModelRepo(...).componentId)
  return try loadFromDisk(path)
}
```

---

## Key Patterns

| Pattern | What | Why | Example |
|---------|------|-----|---------|
| **Enum** | `YourModelRepo: CaseIterable` | Type safety + iteration | `YourModelRepo.allCases` |
| **ComponentFile** | List all required files | No surprises during download | 12 files for Qwen3-TTS |
| **ComponentDescriptor** | Model + files + memory | Single source of truth | One per variant |
| **Lazy Init** | Module-level `let _register...` | Thread-safe, once-only | Called from `manager.init()` |
| **ensureComponentReady()** | Download before load | Atomic, no partial downloads | Called in `loadModel()` |

---

## Common Mistakes to Avoid

### ❌ Don't: Hard-code model paths

```swift
// WRONG
let path = "/Users/me/Models/model.safetensors"
```

### ✅ Do: Use Acervo for paths

```swift
// RIGHT
let path = Acervo.modelPath(for: componentId)
```

---

### ❌ Don't: Skip file declarations

```swift
// WRONG - Acervo won't know what to download
private let files: [ComponentFile] = []
```

### ✅ Do: Declare all files

```swift
// RIGHT
private let files: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "model.safetensors"),
  // ... every single file
]
```

---

### ❌ Don't: Load model before ensureComponentReady()

```swift
// WRONG - Files might not be present
let model = try await loadModel(path)
```

### ✅ Do: Download first, then load

```swift
// RIGHT
try await Acervo.ensureComponentReady(componentId)
let model = try await loadModel(path)
```

---

### ❌ Don't: Store model paths

```swift
// WRONG - Path could change
let cachedPath = Acervo.modelPath(for: id)
// ... later ...
loadModel(from: cachedPath)  // Might be stale
```

### ✅ Do: Look up path each time

```swift
// RIGHT
let path = Acervo.modelPath(for: id)  // Fresh lookup
loadModel(from: path)
```

---

### ❌ Don't: Forget lazy init trigger

```swift
// WRONG - Models never registered
public init() {
  // Missing: _ = _registerYourModelComponents
}
```

### ✅ Do: Reference lazy let

```swift
// RIGHT
public init() {
  _ = _registerYourModelComponents  // Trigger!
}
```

---

## Memory Calculation

```
minimumMemoryBytes = estimatedSizeBytes × headroomMultiplier

Example (VoxAlta):
  - Model size: 3.4 GB
  - Headroom: 1.5× (for KV caches + activations)
  - Required: 3.4 GB × 1.5 = 5.1 GB
```

**Common multipliers**:
- **1.3×** - Lightweight models (minimal overhead)
- **1.5×** - Standard (like VoxAlta)
- **2.0×** - Heavy (batch processing, large activations)

---

## Testing Checklist

```swift
// ✅ Registration test
func testAllModelsRegistered() {
  let manager = YourManager()
  for model in YourModelRepo.allCases {
    XCTAssertNotNil(Acervo.component(model.componentId))
  }
}

// ✅ File count test
func testFileCount() {
  let manager = YourManager()
  for model in YourModelRepo.allCases {
    let desc = Acervo.component(model.componentId)!
    XCTAssertEqual(desc.files.count, 12)  // Your number
  }
}

// ✅ Download test
func testDownload() async throws {
  let manager = YourManager()
  let model = try await manager.loadModel(
    repo: YourModelRepo.small.rawValue
  )
  XCTAssertNotNil(model)
}
```

---

## File Locations

| Item | Location |
|------|----------|
| **Downloaded models** | Resolved at runtime via `Acervo.sharedModelsDirectory` |
| **Model metadata** | `Acervo.component(componentId)` |
| **Model path** | `Acervo.modelPath(for: componentId)` |
| **Deprecated flag** | `metadata: ["deprecated": "true"]` |

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| Models not registered | Lazy init not triggered | Check `init()` has `_ = _registerYourModelComponents` |
| Download fails | Missing files in descriptor | Verify file list: `ls -R` on HF repo |
| "File not found" | Wrong file path | Check `relativePath` matches HF structure exactly |
| Memory warning | Multiplier too aggressive | Reduce from 1.5× to 1.3× |
| Models download again | Path incorrect | Use `Acervo.modelPath()` not hardcoded paths |

---

## Links

- **Full Template**: `COMPONENTDESCRIPTOR_ADOPTION_TEMPLATE.md`
- **Implementation Checklist**: `COMPONENTDESCRIPTOR_IMPLEMENTATION_CHECKLIST.md`
- **Audit Report**: `SWIFTVOXALTA_AUDIT_REPORT.md`
- **SwiftVoxAlta Source**: `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

---

## Key Takeaways

1. **Enumerate models** for type safety
2. **Declare all files** upfront (no discovery)
3. **Calculate memory** with headroom multiplier
4. **Register lazily** at module init
5. **Download first** with `ensureComponentReady()`
6. **Test thoroughly** with `allCases`

---

**Last Updated**: 2026-04-18  
**Print-Friendly**: Yes (fits 1 page)  
**Reference**: SwiftVoxAlta (7 models, 100% coverage)
