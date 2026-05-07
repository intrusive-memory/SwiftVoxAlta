# SwiftVoxAlta Telemetry Requirements

**Priority**: 🔴 CRITICAL  
**Status**: Not Started  
**Effort Estimate**: 4-6 hours  
**Dependencies**: None

## Context

Produciesta telemetry revealed that `VoxAltaModelManager.unloadModel()` doesn't actually free memory:
- Before unload: 4,418.9 MB
- After unload: 4,442.5 MB (+23.6 MB instead of -3,400 MB)

SwiftVoxAlta is the **primary suspect** for the memory leak. We need visibility into:
1. Model loading/unloading lifecycle
2. mlx-swift model retention
3. Voice cache state
4. Metal/GPU buffer allocations

## Objectives

1. **Prove model unload works** (or doesn't work)
2. **Identify what retains the model** after `unloadModel()` is called
3. **Track voice cache growth** across episodes
4. **Monitor mlx-swift internal state** (if accessible)

## Telemetry Points

### 1. VoxAltaModelManager Lifecycle

**File**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

Add telemetry to these methods:

#### `loadModel(repo:)` - Before and After
```swift
public func loadModel(repo: String) async throws -> any SpeechGenerationModel {
    // TELEMETRY: Before load
    await telemetry?.capture(.modelLoadStart(repo: repo, cacheHit: cachedModel != nil))
    
    // ... existing load logic ...
    
    // TELEMETRY: After load (with memory usage)
    let modelSizeMB = await estimateModelMemoryUsage()
    await telemetry?.capture(.modelLoadComplete(repo: repo, sizeMB: modelSizeMB))
    
    return model
}
```

#### `unloadModel()` - Before and After
```swift
public func unloadModel() async {
    // TELEMETRY: Before unload
    let wasLoaded = cachedModel != nil
    let modelSizeMB = await estimateModelMemoryUsage()
    await telemetry?.capture(.modelUnloadStart(loaded: wasLoaded, sizeMB: modelSizeMB))
    
    // Existing unload logic
    cachedModel = nil
    _currentModelRepo = nil
    await MemoryManager.shared.clearGPUCache()
    
    // TELEMETRY: After unload (verify memory actually freed)
    await telemetry?.capture(.modelUnloadComplete(
        freed: modelSizeMB,
        processMemoryMB: getCurrentProcessMemory()
    ))
}
```

### 2. Voice Cache Tracking

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceCache.swift`

Track cache growth:

```swift
public actor VoxAltaVoiceCache {
    // Add telemetry reporting
    public func reportState() -> VoiceCacheTelemetry {
        return VoiceCacheTelemetry(
            entriesCount: voices.count,
            totalBytesCached: voices.values.map(\.count).reduce(0, +),
            topVoicesBySize: voices.sorted { $0.value.count > $1.value.count }.prefix(5)
        )
    }
}
```

### 3. mlx-swift Model Retention

**File**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

Check if mlx-swift retains models internally:

```swift
private func checkMLXRetention() -> MLXRetentionReport {
    // Try to access mlx-swift internals (if possible)
    // This might require reflection or private API access
    
    return MLXRetentionReport(
        activeArrayCount: MLX.Metal.activeArrayCount() ?? -1,
        metalHeapSizeMB: MLX.Metal.currentHeapSize() ?? -1,
        modelRegistrySize: MLXModelRegistry.count() ?? -1  // If this exists
    )
}
```

### 4. Memory Estimation

**File**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

Add helper to estimate model memory:

```swift
private func estimateModelMemoryUsage() async -> Double {
    guard let model = cachedModel else { return 0.0 }
    
    // Try to get actual model size from mlx-swift
    // If not available, estimate from model repo name:
    // "0.6B" → ~1200 MB, "1.7B" → ~3400 MB
    
    if let repo = _currentModelRepo {
        if repo.contains("1.7B") {
            return 3400.0
        } else if repo.contains("0.6B") {
            return 1200.0
        }
    }
    
    return 0.0
}
```

## Data Structures

### Telemetry Events

```swift
public enum VoxAltaTelemetryEvent: Sendable {
    case modelLoadStart(repo: String, cacheHit: Bool)
    case modelLoadComplete(repo: String, sizeMB: Double)
    case modelUnloadStart(loaded: Bool, sizeMB: Double)
    case modelUnloadComplete(freed: Double, processMemoryMB: Double)
    case voiceCacheGrowth(entriesCount: Int, totalMB: Double)
    case metalBufferState(allocatedMB: Double, peakMB: Double)
}
```

### Telemetry Reporter Protocol

```swift
public protocol VoxAltaTelemetryReporter: Sendable {
    func capture(_ event: VoxAltaTelemetryEvent) async
}
```

### Integration with Produciesta

Produciesta will inject telemetry reporter:

```swift
// In Produciesta:
let voxAltaTelemetry = VoxAltaTelemetryAdapter(memoryTelemetry: memoryTelemetry)
await voxAltaProvider.setTelemetry(voxAltaTelemetry)
```

## Implementation Checklist

### Phase 1: Basic Infrastructure (2 hours)
- [ ] Create `VoxAltaTelemetryEvent` enum
- [ ] Create `VoxAltaTelemetryReporter` protocol
- [ ] Add `telemetry` property to `VoxAltaModelManager`
- [ ] Add `setTelemetry()` method to `VoxAltaVoiceProvider`

### Phase 2: Core Instrumentation (2 hours)
- [ ] Instrument `loadModel()` - before/after
- [ ] Instrument `unloadModel()` - before/after
- [ ] Add `estimateModelMemoryUsage()` helper
- [ ] Add `getCurrentProcessMemory()` helper

### Phase 3: Cache & Metal Tracking (1-2 hours)
- [ ] Add `reportState()` to `VoxAltaVoiceCache`
- [ ] Track Metal buffer allocations (if accessible)
- [ ] Check mlx-swift model retention (if accessible)

### Phase 4: Testing (1 hour)
- [ ] Unit test: telemetry events fire correctly
- [ ] Unit test: memory estimation is accurate
- [ ] Integration test: telemetry reports to Produciesta

## Testing Strategy

### Unit Tests

```swift
func testModelLoadTelemetry() async throws {
    let mockTelemetry = MockTelemetryReporter()
    let manager = VoxAltaModelManager()
    await manager.setTelemetry(mockTelemetry)
    
    _ = try await manager.loadModel(repo: "test-repo")
    
    XCTAssertEqual(mockTelemetry.events.count, 2)
    XCTAssertEqual(mockTelemetry.events[0], .modelLoadStart(repo: "test-repo", cacheHit: false))
    XCTAssertEqual(mockTelemetry.events[1], .modelLoadComplete(repo: "test-repo", sizeMB: 3400.0))
}

func testModelUnloadTelemetry() async throws {
    // ... similar test for unload
}
```

### Integration Test (with Produciesta)

Run Produciesta with `--telemetry` and verify SwiftVoxAlta events appear in output:

```bash
bin/produciesta ~/test-project --telemetry | grep "VoxAlta"
```

Expected output:
```
📊 [VoxAlta] Model load start: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16 (cache hit: false)
📊 [VoxAlta] Model load complete: 3400.0 MB
📊 [VoxAlta] Model unload start: 3400.0 MB
📊 [VoxAlta] Model unload complete: freed 0.0 MB ⚠️ LEAKED
```

## Success Criteria

### Must Have
- [x] `loadModel()` reports memory before/after
- [x] `unloadModel()` reports memory before/after
- [x] Telemetry proves whether model is actually freed
- [x] Voice cache state is tracked

### Nice to Have
- [ ] mlx-swift internal state (if accessible)
- [ ] Metal buffer tracking
- [ ] Per-voice memory usage

## Expected Findings

After instrumentation, telemetry should reveal:

**Scenario 1: Model Not Released**
```
Model unload start: 3400.0 MB
Model unload complete: freed 0.0 MB ⚠️
```
→ `cachedModel = nil` doesn't free memory (mlx-swift retains it)

**Scenario 2: Model Released But Metal Buffers Leaked**
```
Model unload start: 3400.0 MB
Model unload complete: freed 3200.0 MB
Metal buffers still allocated: 200.0 MB ⚠️
```
→ Model freed, but Metal buffers not cleared

**Scenario 3: Voice Cache Leak**
```
Voice cache: 150 entries, 2.1 GB ⚠️
```
→ Voice embeddings accumulating

## Next Steps After Instrumentation

1. **Run telemetry test** with Produciesta
2. **Analyze VoxAlta events** in telemetry output
3. **Identify retention source** (model, buffers, cache)
4. **Implement fix** based on findings
5. **Re-test** to verify fix works

## References

- **Produciesta telemetry**: [TELEMETRY_FINDINGS.md](../Produciesta/TELEMETRY_FINDINGS.md)
- **Coordination doc**: [MULTI_REPO_TELEMETRY.md](../Produciesta/MULTI_REPO_TELEMETRY.md)
- **VoxAltaModelManager**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

---

**Ready to start?** Open a new Claude Code window in `/Users/stovak/Projects/SwiftVoxAlta` and follow this REQUIREMENTS document.
