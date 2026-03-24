---
feature_name: "SwiftVoxAlta — Infrastructure Adoption"
iteration: 1
wave: "4.3-4.5"
repository: SwiftVoxAlta
status: refined
depends_on: ["SwiftAcervo v2 (Wave 0)", "SwiftTubería Wave 1.3 (MemoryManager + DeviceCapability)"]
refinement_passes: [atomicity, priority, parallelism, questions]
context_budget: 50
---

# SwiftVoxAlta — Infrastructure Adoption Execution Plan

**Scope**: Adopt SwiftTuberia's infrastructure services (MemoryManager, DeviceCapability) and SwiftAcervo v2's Component Registry while preserving VoxAlta's VoiceProvider interface and mlx-audio-swift TTS generation path unchanged.

**Guiding principle**: This is infrastructure adoption, not pipeline migration. The TTS generation path (autoregressive text-to-audio via Qwen3-TTS) remains in mlx-audio-swift. What changes is the plumbing underneath: model management, memory budgeting, and device detection move to shared infrastructure.

---

## Terminology

> **Mission** — A definable, testable scope of work that decomposes into one or more sorties dispatched to autonomous agents. A mission defines the scope, acceptance criteria, and dependency structure; the sorties are attempts to accomplish the mission.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. A sortie has a defined objective, machine-verifiable entry/exit criteria, and bounded scope (fits within a single agent context window). The term is borrowed from military aviation: one aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase). This plan is a single work unit: the SwiftVoxAlta infrastructure adoption.

---

## Reconnaissance (Pre-Sortie Reference)

This section documents the current state analysis. It is **not a sortie** — it is reference material for all sorties that follow. The reconnaissance is complete.

### Current State

#### VoxAltaModelManager (`Sources/SwiftVoxAlta/VoxAltaModelManager.swift`)
- **Lines 17-88**: `Qwen3TTSModelRepo` enum — 7 HuggingFace repo raw values hardcoded as enum cases
- **Lines 95-117**: `Qwen3TTSModelSize` — hardcoded `knownSizes` dictionary mapping repo strings to byte counts; `headroomMultiplier = 1.5`
- **Lines 129-360**: `VoxAltaModelManager` actor:
  - `migrateIfNeeded()` — calls `Acervo.migrateFromLegacyPaths()` (Acervo v1 API)
  - `isModelInAcervo()` — calls `Acervo.isModelAvailable()` (Acervo v1 API)
  - `loadModel(repo:)` — calls `TTSModelUtils.loadModel(modelRepo:)` from mlx-audio-swift; uses `Qwen3TTSModelSize.knownSizes` for memory check
  - `unloadModel()` — direct `Stream.defaultStream(.gpu).synchronize()` + `Memory.clearCache()` calls (lines 267-268)
  - `checkMemory()` / `validateMemory()` — direct Mach VM stat queries via `queryAvailableMemory()` (lines 332-359)
  - `totalPhysicalMemory` / `availableMemory` — `ProcessInfo.processInfo.physicalMemory` and `queryAvailableMemory()`

#### AppleSiliconInfo (`Sources/SwiftVoxAlta/AppleSiliconInfo.swift`)
- **Lines 16-177**: `AppleSiliconGeneration` enum — 21 cases (M1-M5 families + unknown)
- `hasNeuralAccelerators` — true for M5 variants only
- `current` — cached detection via `sysctlbyname("machdep.cpu.brand_string")`
- Used in `VoxAltaModelManager.loadModel()` (line 232) to log Neural Accelerator status

#### DigaModelManager (`Sources/diga/DigaModelManager.swift`)
- **Lines 5-15**: `TTSModelID` — hardcoded HF repo strings (large, small, voiceDesign) + RAM threshold
- **Lines 18-25**: `TTSModelFiles.required` — hardcoded file list `["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]`
- **Lines 38-123**: `DigaModelManager` actor:
  - `modelsDirectory` — `Acervo.sharedModelsDirectory`
  - `modelDirectory(for:)` — `Acervo.modelDirectory(for:)`
  - `isModelAvailable()` — `Acervo.isModelAvailable()`
  - `downloadModel()` — `Acervo.ensureAvailable(modelId, files:)` with hardcoded file list
  - `recommendedModel()` — `ProcessInfo.processInfo.physicalMemory` for RAM-based selection

#### GPU Cache Clearing Sites (3 locations)
1. `VoxAltaModelManager.unloadModel()` — lines 267-268
2. `VoiceLockManager.createLock()` — lines 99-100
3. `VoiceLockManager.generateAudio()` — lines 267-268

#### VoxAltaConfig (`Sources/SwiftVoxAlta/VoxAltaConfig.swift`)
- Hardcoded HF repo strings in `VoxAltaConfig.default` (lines 50-56): `designModel`, `renderModel`, `analysisModel`

### Files Inventory

| File | Change Type | Sortie |
|------|-------------|--------|
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Major rewrite | 1, 2, 3, 5, 6 |
| `Sources/SwiftVoxAlta/AppleSiliconInfo.swift` | Thin wrapper around DeviceCapability | 4 |
| `Sources/SwiftVoxAlta/VoiceLockManager.swift` | GPU cache clearing | 5 |
| `Sources/SwiftVoxAlta/VoxAltaConfig.swift` | Remove hardcoded HF strings | 6 |
| `Sources/diga/DigaModelManager.swift` | Acervo v2 migration | 2, 6 |
| `Package.swift` | Add Tuberia dependency | 3 |
| `Tests/SwiftVoxAltaTests/VoxAltaModelManagerTests.swift` | Update for async signatures | 7 |
| `Tests/SwiftVoxAltaTests/AppleSiliconInfoTests.swift` | Update for DeviceCapability delegation | 7 |
| `Tests/DigaTests/DigaModelManagerTests.swift` | Update for Acervo v2 | 7 |
| New: `Tests/SwiftVoxAltaTests/ComponentRegistrationTests.swift` | New test file | 8 |
| New: `Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift` | New test file | 8 |

### External Dependencies
- SwiftAcervo v2 must expose: `ComponentDescriptor`, `Acervo.registerComponent()`, `Acervo.ensureComponentReady()`, `Acervo.component()`
- SwiftTuberia must expose: `MemoryManager.shared`, `DeviceCapability.current`, `MemoryManager.clearGPUCache()`

### Notes
- `Qwen3TTSModelRepo` enum is public API used by `VoiceLockManager`, `VoxAltaVoiceProvider`, `DigaEngine`, and external consumers. It must be preserved as-is during migration; only its backing data source changes.
- `VoxAltaConfig.default` hardcodes 3 HF repo strings — these should reference ComponentDescriptor IDs after migration.
- The `TTSModelFiles.required` list in DigaModelManager becomes unnecessary once downloads go through `ensureComponentReady()`.

---

## Sortie 1: Acervo Component Registration

**Priority**: 18.5 — Foundation sortie; 6 downstream sorties depend on component descriptors being registered. Highest dependency depth.

**Model**: sonnet — New API integration (Acervo v2), moderate complexity, well-specified.

**Estimated turns**: 17 / 50

### Objective
Define 7 `ComponentDescriptor` entries for all Qwen3-TTS model variants. Register them at import time so they are queryable via the Acervo Component Registry. Mark the 4-bit variant as deprecated.

### Files
| File | Action |
|------|--------|
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Add `ComponentDescriptor` declarations and registration block |

### Implementation

Add a new section (after the `Qwen3TTSModelRepo` enum, before `VoxAltaModelManager`) that declares and registers 6+1 component descriptors:

```swift
// MARK: - Acervo Component Registration

extension Qwen3TTSModelRepo {
    /// The Acervo component ID for this model variant.
    public var componentId: String {
        switch self {
        case .base1_7B:         return "qwen3-tts-base-1.7b"
        case .base0_6B:         return "qwen3-tts-base-0.6b"
        case .customVoice1_7B:  return "qwen3-tts-custom-1.7b"
        case .customVoice0_6B:  return "qwen3-tts-custom-0.6b"
        case .voiceDesign1_7B:  return "qwen3-tts-voicedesign-1.7b"
        case .base1_7B_8bit:    return "qwen3-tts-base-1.7b-8bit"
        case .base1_7B_4bit:    return "qwen3-tts-base-1.7b-4bit"
        }
    }
}
```

Register all 7 descriptors (6 active + 1 deprecated):

| Component ID | HuggingFace Repo | Type | Size | Deprecated |
|---|---|---|---|---|
| `qwen3-tts-base-1.7b` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` | languageModel | ~3.4 GB | No |
| `qwen3-tts-base-0.6b` | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` | languageModel | ~1.2 GB | No |
| `qwen3-tts-custom-1.7b` | `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16` | languageModel | ~3.4 GB | No |
| `qwen3-tts-custom-0.6b` | `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16` | languageModel | ~1.2 GB | No |
| `qwen3-tts-voicedesign-1.7b` | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` | languageModel | ~3.4 GB | No |
| `qwen3-tts-base-1.7b-8bit` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit` | languageModel | ~1.7 GB | No |
| `qwen3-tts-base-1.7b-4bit` | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit` | languageModel | ~850 MB | **Yes** |

The 4-bit descriptor includes `metadata["deprecated": "true"]`.

The `required` file list (`config.json`, `tokenizer.json`, `tokenizer_config.json`, `model.safetensors`) moves into each `ComponentDescriptor`.

Registration occurs in a module-level initializer or lazy static that runs when SwiftVoxAlta is first used.

### Entry Criteria
- SwiftAcervo v2 `ComponentDescriptor` type and `Acervo.registerComponent()` API are available in the resolved dependency

### Exit Criteria
- `Qwen3TTSModelRepo` has a `.componentId` computed property mapping each of the 7 cases to its Acervo ID
- All 7 `ComponentDescriptor` entries are defined with `huggingFaceRepo`, `type`, `minimumMemoryBytes`, and `requiredFiles` fields
- Registration block exists and runs at module initialization (lazy static or `@_silgen_name` initializer)
- Build succeeds: `make build` exits 0
- All existing tests pass: `make test` exits 0
- Grep verification: `grep -c "registerComponent" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 7

### Notes
- `Qwen3TTSModelRepo` keeps its `rawValue` (HF repo string) for backward compatibility with mlx-audio-swift's `TTSModelUtils.loadModel(repo:)`.
- `Qwen3TTSModelSize.knownSizes` dictionary is NOT removed yet (that happens in Sortie 6). During the transition, both the old dictionary and the new descriptors coexist.

---

## Sortie 2: Download Migration

**Priority**: 14.5 — Directly depends on Sortie 1. Enables component-based download path used by Sorties 6, 7, 8.

**Model**: sonnet — API migration with 2 files, moderate complexity.

**Estimated turns**: 18 / 50

### Objective
Switch model downloading from `Acervo.ensureAvailable(modelId, files:[...])` to `Acervo.ensureComponentReady(componentId)`. Remove the hardcoded `TTSModelFiles` enum from DigaModelManager.

### Files
| File | Action |
|------|--------|
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Update `loadModel(repo:)` to call `ensureComponentReady` before `TTSModelUtils.loadModel()` |
| `Sources/diga/DigaModelManager.swift` | Update `downloadModel()` to use `ensureComponentReady`; remove `TTSModelFiles` enum |

### Implementation

**VoxAltaModelManager.loadModel(repo:)**:
```swift
// Before:
let model = try await TTSModelUtils.loadModel(modelRepo: repo)

// After:
let modelRepo = Qwen3TTSModelRepo(rawValue: repo)
if let modelRepo {
    try await Acervo.ensureComponentReady(modelRepo.componentId)
}
let model = try await TTSModelUtils.loadModel(modelRepo: repo)
```

The key insight: `TTSModelUtils.loadModel()` from mlx-audio-swift handles the actual weight loading. VoxAlta's responsibility is ensuring the files are on disk before calling it. After migration, `ensureComponentReady` replaces the implicit download-on-demand that `TTSModelUtils` may do internally.

**DigaModelManager.downloadModel()**:
```swift
// Before:
try await Acervo.ensureAvailable(modelId, files: TTSModelFiles.required) { ... }

// After:
let componentId = Qwen3TTSModelRepo(rawValue: modelId)?.componentId ?? modelId
try await Acervo.ensureComponentReady(componentId) { ... }
```

**DigaModelManager**: Remove `TTSModelFiles` enum entirely. Required files are now declared in the `ComponentDescriptor`.

### Entry Criteria
- Sortie 1 complete (all 7 ComponentDescriptors registered and queryable)
- SwiftAcervo v2 `Acervo.ensureComponentReady(id)` API available

### Exit Criteria
- `TTSModelFiles` enum removed from `DigaModelManager.swift`: `grep -c "TTSModelFiles" Sources/diga/DigaModelManager.swift` returns 0
- Zero calls to `Acervo.ensureAvailable` with a `files:` parameter: `grep -c "ensureAvailable.*files:" Sources/` returns 0
- `VoxAltaModelManager.loadModel()` calls `ensureComponentReady` before `TTSModelUtils.loadModel()`
- Build succeeds: `make build` exits 0
- All existing tests pass: `make test` exits 0

### Notes
- `DigaModelManager` still uses `Acervo.sharedModelsDirectory`, `Acervo.modelDirectory(for:)`, and `Acervo.isModelAvailable()` — these are Acervo v1 APIs that may persist or be replaced by Component Registry queries. Assess during implementation.
- `VoxAltaModelManager.migrateIfNeeded()` calls `Acervo.migrateFromLegacyPaths()` — this stays as-is (it is Acervo's migration, not VoxAlta's concern).

---

## Sortie 3: Memory Manager Adoption + Tuberia Dependency

**Priority**: 16.0 — Foundation sortie: adds SwiftTuberia to Package.swift (required by Sorties 4, 5). Also replaces memory queries, which unblocks Sortie 6.

**Model**: sonnet — Package dependency wiring + API migration, moderate complexity.

**Estimated turns**: 20 / 50

### Objective
Add SwiftTuberia as a dependency in Package.swift. Replace direct Mach VM stat queries in `VoxAltaModelManager` with SwiftTuberia's `MemoryManager`. Keep the 1.5x headroom multiplier in VoxAlta.

### Files
| File | Action |
|------|--------|
| `Package.swift` | Add `SwiftTuberia` dependency; add `Tubería` product to SwiftVoxAlta target |
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Replace `queryAvailableMemory()`, `checkMemory()`, `validateMemory()`, `totalPhysicalMemory`, `availableMemory` with MemoryManager delegation |

### Implementation

**Package.swift** — add dependency:
```swift
.package(url: "https://github.com/intrusive-memory/SwiftTuberia.git", branch: "main"),
```

Add to SwiftVoxAlta target dependencies:
```swift
.product(name: "Tubería", package: "SwiftTuberia"),
```

**VoxAltaModelManager** — replace memory queries:

| Current | Replacement |
|---------|-------------|
| `queryAvailableMemory()` (private static, Mach VM stats) | `await MemoryManager.shared.availableMemory` |
| `systemPageSize` (private static, sysctl) | Remove (MemoryManager handles internally) |
| `checkMemory(forModelSizeBytes:)` | Delegate to `MemoryManager.shared.softCheck(requiredBytes:)` after applying 1.5x |
| `validateMemory(forModelSizeBytes:)` | Delegate to `MemoryManager.shared.hardValidate(requiredBytes:)` after applying 1.5x |
| `totalPhysicalMemory` | `MemoryManager.shared.totalPhysicalMemory` |
| `availableMemory` | `await MemoryManager.shared.availableMemory` |

The 1.5x headroom multiplier stays in VoxAlta:
```swift
public func checkMemory(forModelSizeBytes requiredBytes: Int) async -> Bool {
    let requiredWithHeadroom = UInt64(Double(requiredBytes) * Qwen3TTSModelSize.headroomMultiplier)
    return await MemoryManager.shared.softCheck(requiredBytes: requiredWithHeadroom)
}
```

**Note**: `checkMemory` and `validateMemory` become `async` (they weren't before because `queryAvailableMemory` was synchronous). Callers already call these from async contexts, so this is a source-compatible change.

### Entry Criteria
- SwiftTuberia Wave 1.3 complete (MemoryManager available in `Tubería` target)
- Sortie 1 complete (ComponentDescriptors provide `minimumMemoryBytes` for each model)

### Exit Criteria
- `Package.swift` includes SwiftTuberia dependency: `grep -c "SwiftTuberia" Package.swift` returns >= 1
- `Package.swift` includes Tubería product in SwiftVoxAlta target: `grep -c "Tubería" Package.swift` returns >= 1
- `queryAvailableMemory()` private method removed: `grep -c "queryAvailableMemory" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 0
- `systemPageSize` private property removed: `grep -c "systemPageSize" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 0
- Zero direct `vm_statistics64`, `host_statistics64`, or `mach_host_self()` calls in SwiftVoxAlta sources: `grep -rc "vm_statistics64\|host_statistics64\|mach_host_self" Sources/SwiftVoxAlta/` returns 0
- `Qwen3TTSModelSize.headroomMultiplier` (1.5) still present: `grep -c "headroomMultiplier" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns >= 1
- Build succeeds: `make build` exits 0
- All existing tests pass: `make test` exits 0

### Notes
- `DigaModelManager.recommendedModel()` uses `ProcessInfo.processInfo.physicalMemory` for RAM-based model selection. This is a low-priority nonisolated convenience and stays as-is for this sortie.
- The `Qwen3TTSModelSize.knownSizes` dictionary is still used in `loadModel()` to look up estimated sizes. After Sortie 1, these sizes are also in ComponentDescriptors. During this sortie, switch to reading from descriptors where possible.

---

## Sortie 4: Device Capability Migration

**Priority**: 10.5 — Leaf sortie (no downstream sorties depend on it). Lower risk because Option A preserves backward compatibility. Can run in parallel with Sortie 5.

**Model**: sonnet — API delegation pattern, moderate complexity.

**Estimated turns**: 19 / 50

**Parallel group**: B (can run simultaneously with Sortie 5 after Sortie 3 completes)

### Objective
Rewrite `AppleSiliconGeneration` in `AppleSiliconInfo.swift` as a thin wrapper that delegates to SwiftTuberia's `DeviceCapability`. Preserve all 21 enum cases and the public API surface for backward compatibility (Option A).

### Decision: Option A (Thin Wrapper)
Option A is confirmed. Option B (removal) is rejected because external consumers (Produciesta, SwiftEchada) reference `AppleSiliconGeneration` directly. Breaking their API surface is out of scope for this infrastructure adoption mission.

### Files
| File | Action |
|------|--------|
| `Sources/SwiftVoxAlta/AppleSiliconInfo.swift` | Rewrite as thin wrapper: `.current` and `.hasNeuralAccelerators` delegate to `DeviceCapability`; enum cases and `CaseIterable` conformance preserved |
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | No change needed (Option A makes delegation internal to `AppleSiliconGeneration`) |

### Implementation

```swift
public enum AppleSiliconGeneration: String, Sendable, CaseIterable {
    // ... all 21 cases unchanged for backward compatibility ...

    public var hasNeuralAccelerators: Bool {
        DeviceCapability.current.hasNeuralAccelerators
    }

    public static var current: AppleSiliconGeneration {
        // Map DeviceCapability.chipGeneration to local enum
        mapFromDeviceCapability(DeviceCapability.current)
    }
}
```

### Feature Detection Mapping

| AppleSiliconGeneration property | DeviceCapability equivalent |
|---|---|
| `.current` | `DeviceCapability.current.chipGeneration` |
| `.hasNeuralAccelerators` | `DeviceCapability.current.hasNeuralAccelerators` |
| `.rawValue` (e.g., "M5 Pro") | `DeviceCapability.current.chipName` |
| `CaseIterable.allCases` | Not applicable (DeviceCapability is a struct, not enum) — CaseIterable stays on the enum |

### Entry Criteria
- Sortie 3 complete (Tuberia dependency in Package.swift, `import Tubería` available)
- SwiftTuberia's `DeviceCapability.current` API available and documented

### Exit Criteria
- `AppleSiliconGeneration.current` delegates to `DeviceCapability.current` internally: `grep -c "DeviceCapability" Sources/SwiftVoxAlta/AppleSiliconInfo.swift` returns >= 2
- `AppleSiliconGeneration.hasNeuralAccelerators` delegates to `DeviceCapability.current.hasNeuralAccelerators`
- All 21 enum cases still present: `grep -c "case " Sources/SwiftVoxAlta/AppleSiliconInfo.swift` returns 21 (or 22 including `unknown`)
- No direct `sysctlbyname("machdep.cpu.brand_string")` calls: `grep -c "machdep.cpu.brand_string" Sources/SwiftVoxAlta/AppleSiliconInfo.swift` returns 0
- `CaseIterable` conformance preserved: `grep -c "CaseIterable" Sources/SwiftVoxAlta/AppleSiliconInfo.swift` returns >= 1
- Build succeeds: `make build` exits 0
- Existing `AppleSiliconInfoTests` pass: `make test` exits 0

### Notes
- The `AppleSiliconInfoTests.swift` test file checks all 21 cases, raw values, CaseIterable count, and caching. These tests should pass without modification since the public API surface is unchanged.
- `VoxAltaModelManager.loadModel()` (line 232) uses `AppleSiliconGeneration.current` — no change needed because Option A makes the delegation invisible to callers.

---

## Sortie 5: GPU Cache Clearing

**Priority**: 11.0 — Leaf sortie with minor downstream impact. Small scope (3 call sites, same pattern). Can run in parallel with Sortie 4.

**Model**: haiku — Simple mechanical replacement at 3 call sites. Well-specified pattern. No ambiguity.

**Estimated turns**: 18 / 50

**Parallel group**: B (can run simultaneously with Sortie 4 after Sortie 3 completes)

### Objective
Replace direct MLX GPU calls (`Stream.defaultStream(.gpu).synchronize()` + `Memory.clearCache()`) with `MemoryManager.clearGPUCache()` at all 3 call sites.

### Files
| File | Action |
|------|--------|
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Replace GPU calls in `unloadModel()` (lines 267-268) |
| `Sources/SwiftVoxAlta/VoiceLockManager.swift` | Replace GPU calls in `createLock()` (lines 99-100) and `generateAudio()` (lines 267-268) |

### Implementation

All 3 call sites follow the same pattern:
```swift
// Before:
Stream.defaultStream(.gpu).synchronize()
Memory.clearCache()

// After:
await MemoryManager.shared.clearGPUCache()
```

**Signature impact**:
- `VoxAltaModelManager.unloadModel()` — currently synchronous (`public func unloadModel()`). Must become `public func unloadModel() async`. All callers already await on the actor, so this is source-compatible.
- `VoiceLockManager.createLock()` — already `async throws`, no signature change needed.
- `VoiceLockManager.generateAudio()` — already `async throws`, no signature change needed.

**Import change**: Remove `@preconcurrency import MLX` from files that no longer reference `Stream` or `Memory` directly. `VoiceLockManager.swift` still imports MLX for `MLXArray`, so the import stays but `@preconcurrency` may be removable.

**Preserve the AGX crash prevention comment**: The comment explaining WHY GPU cache clearing is needed ("Without this, loading a new model can crash in AGX::ComputeContext due to stale Metal command buffers") must be kept at each call site.

### Entry Criteria
- Sortie 3 complete (MemoryManager imported and available)
- SwiftTuberia `MemoryManager.clearGPUCache()` API available

### Exit Criteria
- Zero `Stream.defaultStream(.gpu).synchronize()` calls: `grep -rc "Stream.defaultStream" Sources/SwiftVoxAlta/` returns 0
- Zero direct `Memory.clearCache()` calls: `grep -rc "Memory.clearCache" Sources/SwiftVoxAlta/` returns 0
- Three `MemoryManager.shared.clearGPUCache()` calls present: `grep -rc "clearGPUCache" Sources/SwiftVoxAlta/` returns 3
- `unloadModel()` signature is `async`: `grep "func unloadModel.*async" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1 match
- AGX crash prevention comment preserved: `grep -c "AGX\|stale Metal" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns >= 1
- Build succeeds: `make build` exits 0
- All existing tests pass: `make test` exits 0

### Notes
- `MemoryManager.clearGPUCache()` performs the same two MLX calls internally, so behavior is identical. The benefit is that MemoryManager can update its internal tracking of GPU memory state.

---

## Sortie 6: Cleanup — Remove Hardcoded Constants

**Priority**: 12.0 — Cleanup sortie that removes technical debt. Depends on Sorties 1-5. Unblocks Sorties 7-8 (tests need the final API shape).

**Model**: sonnet — Multi-file cleanup across 3 files, requires understanding of what was already removed in prior sorties.

**Estimated turns**: 21 / 50

### Objective
Remove all hardcoded file lists, size dictionaries, and HuggingFace repo string literals from VoxAltaModelManager, VoxAltaConfig, and DigaModelManager. All model knowledge lives in ComponentDescriptor declarations and `Qwen3TTSModelRepo` enum raw values.

### Files
| File | Action |
|------|--------|
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | Remove `Qwen3TTSModelSize.knownSizes` dictionary; model sizes come from ComponentDescriptors |
| `Sources/SwiftVoxAlta/VoxAltaConfig.swift` | Replace hardcoded HF strings in `VoxAltaConfig.default` with `Qwen3TTSModelRepo` enum references |
| `Sources/diga/DigaModelManager.swift` | Remove `TTSModelID` enum; use `Qwen3TTSModelRepo` cases instead |

### Implementation

**Remove `Qwen3TTSModelSize.knownSizes`**:
```swift
// Before:
if let estimatedSize = Qwen3TTSModelSize.knownSizes[repo] {
    checkMemory(forModelSizeBytes: estimatedSize)
}

// After:
if let modelRepo = Qwen3TTSModelRepo(rawValue: repo),
   let descriptor = Acervo.component(modelRepo.componentId) {
    await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
}
```

Keep `Qwen3TTSModelSize.headroomMultiplier` (1.5) — this is VoxAlta-specific, not model metadata.

**Remove `TTSModelID` from DigaModelManager**:
```swift
// Before:
static let large = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

// After: Use Qwen3TTSModelRepo.base1_7B.rawValue or .componentId
```

**VoxAltaConfig.default**: Replace hardcoded strings with references to `Qwen3TTSModelRepo` enum values:
```swift
public static let `default` = VoxAltaConfig(
    designModel: Qwen3TTSModelRepo.voiceDesign1_7B.rawValue,
    renderModel: Qwen3TTSModelRepo.base1_7B.rawValue,
    analysisModel: "mlx-community/Qwen3-4B-4bit",  // Not a TTS model, keep as-is
    candidateCount: 3,
    outputFormat: .wav
)
```

### Entry Criteria
- Sorties 1-5 all complete (component registration, download migration, memory manager, device capability, GPU cache clearing)
- All existing tests passing before starting cleanup

### Exit Criteria
- `Qwen3TTSModelSize.knownSizes` dictionary removed: `grep -c "knownSizes" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 0
- `TTSModelID` enum removed from DigaModelManager: `grep -c "TTSModelID" Sources/diga/DigaModelManager.swift` returns 0
- `TTSModelFiles` enum removed from DigaModelManager (if not already in Sortie 2): `grep -c "TTSModelFiles" Sources/diga/DigaModelManager.swift` returns 0
- No hardcoded HuggingFace repo string literals outside `Qwen3TTSModelRepo.rawValue` declarations: `grep -rn "mlx-community/Qwen3-TTS" Sources/ | grep -v "Qwen3TTSModelRepo" | grep -v "analysisModel"` returns 0 matches
- `VoxAltaConfig.default` uses `Qwen3TTSModelRepo` enum references: `grep -c "Qwen3TTSModelRepo" Sources/SwiftVoxAlta/VoxAltaConfig.swift` returns >= 2
- `headroomMultiplier` still present: `grep -c "headroomMultiplier" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns >= 1
- Build succeeds: `make build` exits 0
- All existing tests pass: `make test` exits 0

### Notes
- `Qwen3TTSModelRepo` itself keeps its raw values (HF repo strings). These are the canonical mapping between VoxAlta's type-safe model selection and mlx-audio-swift's string-based `TTSModelUtils.loadModel(repo:)`. The enum is the single source of truth for repo strings.
- The `analysisModel` in `VoxAltaConfig` (`mlx-community/Qwen3-4B-4bit`) is an LLM, not a TTS model, and is outside VoxAlta's scope. Leave it as a hardcoded string for now.

---

## Sortie 7: Update Existing Tests for New APIs

**Priority**: 9.0 — Must follow Sortie 6 (needs final API shape). Verifies all prior sorties.

**Model**: sonnet — Test updates require understanding both old and new APIs, moderate complexity.

**Estimated turns**: 20 / 50

### Objective
Update the 3 existing test files whose APIs changed during Sorties 1-6. No new test files are created in this sortie.

### Files
| File | Action |
|------|--------|
| `Tests/SwiftVoxAltaTests/VoxAltaModelManagerTests.swift` | Update `MemoryCheckTests` and `MemoryValidationTests` for async signatures; update `AcervoIntegrationTests` for Component Registry queries |
| `Tests/SwiftVoxAltaTests/AppleSiliconInfoTests.swift` | Verify tests pass with DeviceCapability delegation (Option A: minimal changes expected) |
| `Tests/DigaTests/DigaModelManagerTests.swift` | Remove `TestTTSModelFiles` replicated enum; remove `requiredModelFiles()` test; update `modelConstants()` to reference `Qwen3TTSModelRepo` |

### Tests That Stay Unchanged
Per REQUIREMENTS.md V6.1, these test files require NO changes:
- `VoxAltaVoiceCacheTests.swift` — voice cache operations
- `VoiceLockManagerTests.swift` — VoiceLock creation/usage
- `AudioConversionTests.swift` — MLXArray to WAV conversion
- `ConsistencyTests.swift` — type consistency checks
- `ErrorPathTests.swift` — error handling
- `TypeTests.swift` — type conformance
- `VoxAltaErrorTests.swift` — error descriptions
- `DigaBinaryIntegrationTests.swift` — CLI integration
- `DigaEngineTests.swift` — engine orchestration
- `DigaVoiceStoreTests.swift` — voice persistence
- `DigaVoxIntegrationTests.swift` — .vox file handling
- `DigaVersionTests.swift` — version constant
- `DigaReleaseTests.swift` — release validation
- `DigaAudioFileWriterTests.swift` — audio file output
- `DigaAudioPlaybackTests.swift` — speaker playback

### Specific Changes

**VoxAltaModelManagerTests.swift**:
- `MemoryCheckTests` — `checkMemory()` is now `async`; add `await` to all call sites
- `MemoryValidationTests` — `validateMemory()` is now `async`; add `await` to all call sites
- `AcervoIntegrationTests` — update any tests that reference `Acervo.isModelAvailable()` to use Component Registry queries

**AppleSiliconInfoTests.swift**:
- Verify all 21 cases, raw values, CaseIterable count, and caching tests still pass
- If any test directly calls `sysctlbyname`, update to test via `AppleSiliconGeneration.current` instead

**DigaModelManagerTests.swift**:
- Remove `TestTTSModelFiles` replicated enum (source enum is gone)
- Remove `requiredModelFiles()` test (file lists now in ComponentDescriptors)
- Update `modelConstants()` to reference `Qwen3TTSModelRepo` instead of `TestTTSModelID`

### Entry Criteria
- Sorties 1-6 all complete
- Build succeeds: `make build` exits 0

### Exit Criteria
- Zero references to removed types in test files: `grep -rc "TTSModelFiles\|TestTTSModelFiles\|TestTTSModelID\|knownSizes" Tests/` returns 0
- All test methods in the 3 modified files compile and pass: `make test` exits 0
- No `sleep()` or fixed timeout calls added: `grep -rc "sleep\|Thread.sleep\|Task.sleep" Tests/SwiftVoxAltaTests/VoxAltaModelManagerTests.swift Tests/SwiftVoxAltaTests/AppleSiliconInfoTests.swift Tests/DigaTests/DigaModelManagerTests.swift` returns 0

### Notes
- Per REQUIREMENTS.md V6.4: unit tests must use injected/mock dependencies.
- Integration tests requiring real model weights or GPU remain in the existing integration test target and are not modified.

---

## Sortie 8: New Integration Tests

**Priority**: 8.0 — Final verification sortie. Creates new test files that validate the entire infrastructure adoption.

**Model**: sonnet — New test creation requires understanding Acervo v2 and MemoryManager APIs plus mock injection patterns.

**Estimated turns**: 22 / 50

### Objective
Create 2 new test files: `ComponentRegistrationTests.swift` (verifying Acervo Component Registry integration) and `MemoryManagerIntegrationTests.swift` (verifying MemoryManager delegation with headroom multiplier). All tests must use injected/mock dependencies.

### Files
| File | Action |
|------|--------|
| New: `Tests/SwiftVoxAltaTests/ComponentRegistrationTests.swift` | Create — verify all 7 ComponentDescriptors are registered and queryable |
| New: `Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift` | Create — verify MemoryManager delegation with headroom multiplier |

### New Tests

**ComponentRegistrationTests.swift**:
```swift
@Suite("Acervo Component Registration")
struct ComponentRegistrationTests {
    @Test("All 7 TTS model variants are registered")
    @Test("Component IDs match Qwen3TTSModelRepo.componentId")
    @Test("4-bit variant has deprecated metadata")
    @Test("ComponentDescriptor huggingFaceRepo matches Qwen3TTSModelRepo.rawValue")
    @Test("ComponentDescriptor minimumMemoryBytes is positive for all variants")
}
```

**MemoryManagerIntegrationTests.swift**:
```swift
@Suite("MemoryManager Integration")
struct MemoryManagerIntegrationTests {
    @Test("checkMemory applies 1.5x headroom before delegating to MemoryManager")
    @Test("validateMemory applies 1.5x headroom before delegating to MemoryManager")
    @Test("clearGPUCache delegates to MemoryManager")
    @Test("availableMemory delegates to MemoryManager")
    @Test("totalPhysicalMemory delegates to MemoryManager")
}
```

### Entry Criteria
- Sortie 7 complete (existing tests updated and passing)
- All 7 ComponentDescriptors registered and queryable (Sortie 1)
- MemoryManager delegation in place (Sortie 3)

### Exit Criteria
- Both new test files exist: `test -f Tests/SwiftVoxAltaTests/ComponentRegistrationTests.swift && test -f Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift`
- ComponentRegistrationTests contains at least 5 test methods: `grep -c "@Test" Tests/SwiftVoxAltaTests/ComponentRegistrationTests.swift` returns >= 5
- MemoryManagerIntegrationTests contains at least 5 test methods: `grep -c "@Test" Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift` returns >= 5
- All new tests use mock/injected dependencies (no real Mach VM stats, no real network calls): `grep -c "Mock\|mock\|stub\|Stub\|protocol.*MemoryProviding" Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift` returns >= 1
- No `sleep()` or fixed timeout calls: `grep -rc "sleep\|Thread.sleep" Tests/SwiftVoxAltaTests/ComponentRegistrationTests.swift Tests/SwiftVoxAltaTests/MemoryManagerIntegrationTests.swift` returns 0
- Build succeeds: `make build` exits 0
- All tests pass (existing + new): `make test` exits 0

### Notes
- Per REQUIREMENTS.md V6.4: unit tests must use injected/mock dependencies. Tests for MemoryManager delegation should inject a mock MemoryManager, not rely on real Mach VM stats.
- The test count (~328) should increase by ~10 with the new test files.

---

## Dependency Structure

```
Sortie 1 (Component Registration)
  ├──► Sortie 2 (Download Migration)
  │      └──► Sortie 3 (Memory Manager + Tuberia Dependency)
  │              ├──► Sortie 4 (Device Capability)      ─┐
  │              └──► Sortie 5 (GPU Cache Clearing)      ─┤ Parallel Group B
  │                                                       │
  │              ◄────────────────────────────────────────┘
  │              Sortie 6 (Cleanup) — waits for 4 AND 5
  │                └──► Sortie 7 (Update Existing Tests)
  │                       └──► Sortie 8 (New Integration Tests)
```

---

## Parallelism Structure

**Critical Path**: Sortie 1 -> Sortie 2 -> Sortie 3 -> Sortie 6 -> Sortie 7 -> Sortie 8 (length: 6 sorties)

Note: Sorties 4 and 5 are off the critical path.

**Parallel Execution Groups**:

- **Group A** (sequential, foundation):
  - Sortie 1: Component Registration (Agent 1 — supervising agent, has build step)
  - Sortie 2: Download Migration (Agent 1 — supervising agent, has build step)
  - Sortie 3: Memory Manager + Tuberia (Agent 1 — supervising agent, has build step)

- **Group B** (parallel, after Group A):
  - Sortie 4: Device Capability (Sub-agent 1 — code changes only, NO BUILD)
  - Sortie 5: GPU Cache Clearing (Sub-agent 2 — code changes only, NO BUILD)
  - **Build verification**: Supervising agent runs `make build && make test` after both sub-agents complete

- **Group C** (sequential, after Group B verified):
  - Sortie 6: Cleanup (Agent 1 — supervising agent, has build step)
  - Sortie 7: Update Existing Tests (Agent 1 — supervising agent, has build step)
  - Sortie 8: New Integration Tests (Agent 1 — supervising agent, has build step)

**Agent Constraints**:
- **Supervising agent**: Handles all sorties with build/compile steps (Sorties 1, 2, 3, 6, 7, 8) and build verification after Group B
- **Sub-agents (2 of max 4)**: Handle Sorties 4 and 5 (code changes only, no build operations)

**Parallelism Metrics**:
- Current: 2 sorties can run simultaneously (Group B)
- Maximum: 2 agents could run simultaneously
- Agent allocation: 1 supervising + 2 sub-agents

---

## Open Questions & Missing Documentation

### Resolved Items

| Sortie | Issue Type | Resolution |
|--------|-----------|------------|
| Sortie 4 | Open question | "Option A vs Option B" — **Resolved: Option A (thin wrapper)**. External consumers depend on `AppleSiliconGeneration` enum. |

### Remaining Items (auto-fixed in this refinement)

| Sortie | Issue Type | Original | Fixed |
|--------|-----------|----------|-------|
| Sortie 2 | Vague criterion | "Model downloads still work end-to-end (manual verification with a clean cache)" | Replaced with: `grep` checks for API call removal + `make test` exits 0 |
| Sortie 4 | Vague criterion | "hasNeuralAccelerators returns identical results to the current implementation" | Replaced with: `AppleSiliconInfoTests` pass + `grep` for DeviceCapability delegation |
| Sortie 4 | Vague criterion | "All 21 chip generation cases still detectable" | Replaced with: `grep -c "case " ...` returns 21+ |
| Sortie 5 | Vague criterion | "GPU cache clearing still functions correctly (stale Metal buffer prevention)" | Replaced with: `grep` for 3 `clearGPUCache` call sites + build/test pass |
| Sortie 5 | Vague criterion | "Generation quality unaffected (verify with manual synthesis test)" | Removed (not machine-verifiable; behavior is identical per implementation notes) |
| Sortie 6 | Vague criterion | "All tests pass" | Replaced with: `make test` exits 0 |
| Sortie 7 (old) | Vague criterion | ">= 90% line coverage on modified/new code" | Removed (no coverage tooling specified; replaced with specific test count checks) |
| Sortie 7 (old) | External dependency | "CI green on macos-26 runner" | Removed (CI is external; local `make test` is the machine-verifiable equivalent) |

### External Dependencies (not blocking, tracked for visibility)

| Dependency | Status | Impact |
|-----------|--------|--------|
| SwiftAcervo v2 APIs (`ComponentDescriptor`, `registerComponent`, `ensureComponentReady`, `component`) | Required before Sortie 1 | Blocks entire mission |
| SwiftTuberia Wave 1.3 APIs (`MemoryManager.shared`, `DeviceCapability.current`, `MemoryManager.clearGPUCache()`) | Required before Sortie 3 | Blocks Sorties 3-8 |

---

## Execution Summary

- **Total sorties**: 8 (was 8 counting Sortie 0; now 8 executable sorties with reconnaissance as reference)
- **Average sortie size**: 19.4 turns (budget: 50)
- **Largest sortie**: Sortie 8 at 22 turns (44% of budget)
- **Smallest sortie**: Sortie 1 at 17 turns (34% of budget)
- **Critical path length**: 6 sorties (Sorties 1 -> 2 -> 3 -> 6 -> 7 -> 8)
- **Parallelism**: 1 supervising agent + 2 sub-agents (Group B: Sorties 4 and 5)
- **Parallel time savings**: ~37 turns saved by running Sorties 4 and 5 concurrently
