---
feature_name: OPERATION LEAKING STETHOSCOPE
starting_point_commit: b8fd93ad52ad1db635a4e9812ede8b3be6d0f26b
mission_branch: feature/telemetry-instrumentation
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVoxAlta Telemetry Instrumentation

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

**Source**: `REQUIREMENTS_telemetry.md`
**Branch**: `feature/telemetry-instrumentation` (worktree at `/Users/stovak/Projects/SwiftVoxAlta-telemetry`)
**Goal**: Add a pluggable telemetry pipeline to SwiftVoxAlta so external consumers (Produciesta) can prove whether `unloadModel()` actually frees memory and whether the voice cache leaks across episodes. **Sortie 1 also empirically tests whether the leak is reproducible inside SwiftVoxAlta's own test process before any instrumentation work is invested.**

**Scope boundary**:
- IN: empirical leak probe (Sortie 1), telemetry types, instrumentation hooks, memory measurement helpers, voice cache reporting, MLX-retention probing (best-effort), unit tests with a mock reporter.
- OUT: changes to Produciesta itself, fixing the leak, building a full Metal buffer profiler.

**Local environment preconditions** (verified before mission start):
- ✅ Cached models at `~/Library/SharedModels/mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16/` and `mlx-community_Qwen3-TTS-12Hz-0.6B-Base-bf16/`. Confirmed present at refinement time. The probe (Sortie 1) loads the 1.7B Base model.
- ✅ macOS, Apple Silicon (M-series). Required for Metal shader compilation in `xcodebuild`.
- ⚠️ `bin/diga` is **not** required for this mission. `make test-integration` is intentionally never invoked.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftVoxAlta Telemetry | `/Users/stovak/Projects/SwiftVoxAlta-telemetry` | 8 | 0 | none |

### Dependency Graph

```
Layer 0:  Sortie 1 (PREFLIGHT LEAK PROBE — empirical)
              ↓ DECISION GATE (see below)
Layer 1:  Sortie 2 (foundation types)
              ↓
Layer 2:  Sortie 3 (memory helpers) ──┬──► Layer 3
          Sortie 4 (telemetry wiring) ─┘   (must serialize: file conflict)
              ↓                  ↓
Layer 3:  Sortie 5 (load/unload) ──► Sortie 7 (MLX/Metal probe)
          Sortie 6 (cache report) ──┐
                                    ▼
Layer 4:                           Sortie 8 (E2E + docs)
```

**Layer rules**: Sorties 3 and 4 both modify `VoxAltaModelManager.swift` and therefore **cannot run in parallel** despite being in the same layer (file-level write conflict). They must serialize: 3 → 4. Sorties 5 and 6 modify disjoint files (manager vs cache+provider) and **can run in parallel**.

### DECISION GATE after Sortie 1

After Sortie 1 produces `LEAK_PROBE_RESULT.md`, the supervisor **must read the verdict line** and surface it to the user before dispatching Sortie 2:

| Verdict | Action |
|---------|--------|
| `LEAK SUSPECTED` | Proceed to Sortie 2. The instrumentation will help isolate the retention point. |
| `NO LEAK` | **PAUSE** — surface to user. The leak Produciesta sees is not reproducible in a fresh process; suspect is upstream (Produciesta-side caching, retain cycle in adapter, multi-process interaction). User decides: continue (telemetry still has value for Produciesta-side observability) or abort. |
| `INCONCLUSIVE` | **PAUSE** — surface to user. Recommend re-running probe with a 3-cycle variant or larger model. User decides whether the mission proceeds with current data. |

The supervisor records the verdict in `SUPERVISOR_STATE.md` Decisions Log so the choice survives across context resets.

---

## Parallelism Structure

**Critical Path** (length 6): Sortie 1 → Sortie 2 → Sortie 4 → Sortie 5 → Sortie 7 → Sortie 8

**Parallel Execution Groups**:
- **Group 0** (sequential): Sortie 1 — supervising agent. Empirical probe. Has build step.
- **Group 1** (sequential): Sortie 2 — supervising agent. Foundation types.
- **Group 2** (sequential, file conflict on `VoxAltaModelManager.swift`): Sortie 3 then Sortie 4 — supervising agent both.
- **Group 3** (parallel — disjoint files):
  - Sortie 5 (`VoxAltaModelManager.swift`) — **supervising agent only** (build + heaviest test surface).
  - Sortie 6 (`VoxAltaVoiceCache.swift` + `VoxAltaVoiceProvider.swift`) — **sub-agent eligible** for code/test writing; supervising agent runs the build/test verification.
- **Group 4** (sequential): Sortie 7 — supervising agent.
- **Group 5** (sequential): Sortie 8 — supervising agent.

**Agent Constraints**:
- **Supervising agent (Agent 0)**: handles all sorties with build/compile steps and any sortie that modifies `VoxAltaModelManager.swift`.
- **Sub-agents (max 4)**: only Sortie 6 is sub-agent eligible. The sub-agent writes code + tests but does NOT run `make build` or `make test-unit`; the supervising agent verifies after handoff.

**Maximum parallelism**: 2 concurrent agents (1 supervising + 1 sub-agent), achievable only during Group 3.

---

## Sortie 1: Preflight Leak Probe (empirical, gates the mission)

**Priority**: ∞ — gates everything. The cheapest way to falsify the mission's premise before any code is written. Runtime ~60–120 seconds (single load+unload of 1.7B Base model from cache).

**Agent**: Supervising agent. Build-heavy.

**Entry criteria**:
- [ ] Worktree at `/Users/stovak/Projects/SwiftVoxAlta-telemetry` on `feature/telemetry-instrumentation`.
- [ ] `test -d ~/Library/SharedModels/mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16` returns 0 (the cached model the probe will load).
- [ ] First sortie — no other prerequisites.

**Tasks**:
1. Create directory `Tests/SwiftVoxAltaTests/Preflight/` and file `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift` containing a single `XCTestCase` subclass `PreflightLeakProbeTests` with one test `testLoadUnloadCycleLeakProbe`. The test:
   - Skips unless `ProcessInfo.processInfo.environment["VOXALTA_RUN_LEAK_PROBE"] == "1"` (use `try XCTSkipIf(...)`). Skipping is the default so the probe never runs in regular `make test-unit`.
   - Captures `rssBeforeMB` via an inline private helper `currentRSSMB()` that wraps `task_info` with `MACH_TASK_BASIC_INFO` (do NOT depend on Sortie 3's `getCurrentProcessMemory` — it doesn't exist yet).
   - Instantiates `VoxAltaModelManager()` and calls `_ = try await manager.loadModel(.base1_7B)`.
   - Captures `rssAfterLoadMB`.
   - Calls `await manager.unloadModel()`.
   - Sleeps 500 ms via `try await Task.sleep(nanoseconds: 500_000_000)` to let MLX async cleanup and autorelease pools drain. **Keep this sleep — it eliminates timing-induced false positives.**
   - Captures `rssAfterUnloadMB`.
   - Computes `loadGrew = rssAfterLoadMB - rssBeforeMB`, `unloadFreed = rssAfterLoadMB - rssAfterUnloadMB`, `netDelta = rssAfterUnloadMB - rssBeforeMB`.
   - Determines verdict:
     - `netDelta > 1000.0` → `"LEAK SUSPECTED"`
     - `netDelta < 200.0` → `"NO LEAK"`
     - else → `"INCONCLUSIVE"`
   - Writes a markdown report to `<projectRoot>/LEAK_PROBE_RESULT.md` (resolve project root from `#filePath` by walking up: file is at `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift`, so 3 `deletingLastPathComponent()` calls reach the worktree root). Report format:
     ```
     # Preflight Leak Probe Result

     Date: <ISO8601>
     Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
     Cycles: 1

     ## RSS measurements (MB)
     Before load:        <rssBeforeMB>
     After load:         <rssAfterLoadMB>
     After unloadModel:  <rssAfterUnloadMB>

     ## Deltas (MB)
     loadGrew:           <loadGrew>
     unloadFreed:        <unloadFreed>
     netDelta:           <netDelta>

     ## Thresholds
     LEAK SUSPECTED if netDelta > 1000.0
     NO LEAK         if netDelta < 200.0
     INCONCLUSIVE    otherwise

     Verdict: <verdict>

     ## Notes
     - RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
     - 500ms drain window between unloadModel() and final RSS sample.
     - This probe runs inside xctest, not Produciesta. Absolute RSS values are not directly comparable across processes; deltas are.
     ```
   - Mirrors the report to stderr via `FileHandle.standardError.write(...)` so the supervisor can parse it from xcodebuild output.
   - Always asserts pass (`XCTAssertTrue(true)`) — interpretation is in the artifact, not the assertion. The verdict is data, not a pass/fail.
2. Run the probe via:
   ```
   VOXALTA_RUN_LEAK_PROBE=1 xcodebuild test \
     -scheme SwiftVoxAlta-Package \
     -destination 'platform=macOS,arch=arm64' \
     -only-testing:SwiftVoxAltaTests/PreflightLeakProbeTests/testLoadUnloadCycleLeakProbe
   ```
   Cache the resulting xcodebuild output to `LEAK_PROBE_XCODEBUILD.log` for diagnostic reference.
3. After the probe completes, read `LEAK_PROBE_RESULT.md` and **echo the `Verdict:` line and all six numeric measurements** to the supervisor's primary output channel so the user (and the supervisor on resume) sees them without opening the file.
4. Write the verdict to `SUPERVISOR_STATE.md` under a new Decisions Log entry: `Sortie 1 verdict: <LEAK SUSPECTED|NO LEAK|INCONCLUSIVE>` with timestamp.

**Exit criteria** (all machine-verifiable):
- [ ] `test -f LEAK_PROBE_RESULT.md` returns 0.
- [ ] `grep -E "^Verdict: (LEAK SUSPECTED|NO LEAK|INCONCLUSIVE)$" LEAK_PROBE_RESULT.md` returns exactly 1.
- [ ] `grep -cE "^(Before load|After load|After unloadModel):" LEAK_PROBE_RESULT.md` returns 3.
- [ ] `grep -cE "^(loadGrew|unloadFreed|netDelta):" LEAK_PROBE_RESULT.md` returns 3.
- [ ] xcodebuild exit code was 0 (test framework executed cleanly; the probe's `XCTAssertTrue(true)` always passes).
- [ ] `grep -c "Sortie 1 verdict:" SUPERVISOR_STATE.md` returns ≥ 1.

**Decision gate (supervisor responsibility, NOT a sortie task)**:
- Read `LEAK_PROBE_RESULT.md` verdict.
- If `LEAK SUSPECTED`: log decision and proceed to Sortie 2.
- If `NO LEAK` or `INCONCLUSIVE`: pause mission, surface verdict + report contents to user, await `/mission-supervisor resume` (proceed) or `/mission-supervisor stop` (abort).

**Failure modes & recovery**:
- Probe throws because model files are missing on disk → fail Sortie 1, escalate to user (entry criterion was supposed to catch this — re-verify cache before retrying).
- Probe throws inside `loadModel` due to mlx-audio-swift bug → write a partial `LEAK_PROBE_RESULT.md` with `Verdict: PROBE FAILED` and the thrown error message. This is an information-bearing failure — surface to user, do not auto-retry to FATAL.
- xcodebuild fails to build the test target → standard build failure path, retry per supervisor's max_retries=3.

---

## Sortie 2: Telemetry foundation types

**Priority**: 21.75 — dependency_depth=6 (everything from here forward depends on this), foundation_score=1, risk=1, complexity=1.5.

**Agent**: Supervising agent.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met **AND** decision gate cleared (supervisor logged a "proceed" decision in `SUPERVISOR_STATE.md`).
- [ ] `git rev-parse --abbrev-ref HEAD` returns `feature/telemetry-instrumentation` (or the worktree's mission branch).

**Tasks**:
1. Create `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` defining the public `VoxAltaTelemetryEvent` enum with all six cases listed in the requirements (`modelLoadStart(repo:cacheHit:)`, `modelLoadComplete(repo:sizeMB:)`, `modelUnloadStart(loaded:sizeMB:)`, `modelUnloadComplete(freed:processMemoryMB:)`, `voiceCacheGrowth(entriesCount:totalMB:)`, `metalBufferState(allocatedMB:peakMB:)`). Conform to `Sendable` and `Equatable`.
2. Create `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryReporter.swift` defining the public `VoxAltaTelemetryReporter` protocol with `func capture(_ event: VoxAltaTelemetryEvent) async`. Conform to `Sendable`.
3. Create `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryTypes.swift` containing two public `Sendable` value types: `VoiceCacheTelemetry` (fields: `entriesCount: Int`, `totalBytesCached: Int`, `topVoicesBySize: [TopVoice]`) and `MLXRetentionReport` (fields: `activeArrayCount: Int`, `metalHeapSizeMB: Double`, `modelRegistrySize: Int`). Define a nested `public struct TopVoice: Sendable, Equatable { public let voiceId: String; public let bytes: Int }`.
4. Create `Tests/SwiftVoxAltaTests/Telemetry/MockTelemetryReporter.swift` — a test-only `actor MockTelemetryReporter: VoxAltaTelemetryReporter` that records every captured event in order and exposes `var events: [VoxAltaTelemetryEvent] { get }`.
5. Create `Tests/SwiftVoxAltaTests/Telemetry/MockTelemetryReporterTests.swift` (smoke test) that pushes one of each of the six event variants to a `MockTelemetryReporter` and asserts `events == [...]` using `Equatable` round-trip.

**Exit criteria** (all machine-verifiable):
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `test -f Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` and same for `VoxAltaTelemetryReporter.swift`, `VoxAltaTelemetryTypes.swift`, `Tests/SwiftVoxAltaTests/Telemetry/MockTelemetryReporter.swift`, `Tests/SwiftVoxAltaTests/Telemetry/MockTelemetryReporterTests.swift` all return 0.
- [ ] `grep -c "public enum VoxAltaTelemetryEvent" Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` returns 1.
- [ ] `grep -c "public protocol VoxAltaTelemetryReporter" Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryReporter.swift` returns 1.
- [ ] `git diff --stat HEAD` shows changes only under `Sources/SwiftVoxAlta/Telemetry/` and `Tests/SwiftVoxAltaTests/Telemetry/` (no modifications to existing source files).

---

## Sortie 3: Memory measurement helpers

**Priority**: 13.5 — dependency_depth=3 (5, 7, 8 use these helpers), foundation_score=1, risk=2 (mach syscalls), complexity=1.0.

**Agent**: Supervising agent.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met.
- [ ] `grep -c "public enum VoxAltaTelemetryEvent" Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` returns 1.

**Tasks**:
1. In `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`, add an **`internal`** (not `private`) helper `func estimateModelMemoryUsage() -> Double` on the `VoxAltaModelManager` actor. It reads `_currentModelRepo` and returns a `Double` of MB: `1.7B` substring → `3400.0`, `0.6B` substring → `1200.0`, otherwise (including `nil`) → `0.0`. Place it in the existing `// MARK: - Memory Validation` section. **`internal` access is required so `@testable import` from the test target can reach it.**
2. Create `Sources/SwiftVoxAlta/Telemetry/ProcessMemory.swift` exporting a file-scope `public func getCurrentProcessMemory() -> Double` (MB) that uses `task_info` with `MACH_TASK_BASIC_INFO` to read `resident_size`, divided by `1024 * 1024`. On `task_info` error, returns `0.0` (do not throw — telemetry should never block the caller). Add a doc comment noting the value is approximate and includes shared memory; use deltas, not absolutes. **This duplicates the inline helper from Sortie 1's probe; the duplication is intentional — Sortie 1 must run before this file exists.**
3. Create `Tests/SwiftVoxAltaTests/Telemetry/ProcessMemoryTests.swift` with two tests:
   - `testGetCurrentProcessMemoryReturnsPositive`: asserts `getCurrentProcessMemory() > 0.0`.
   - `testGetCurrentProcessMemoryIncreasesAfterAllocation`: captures `before`, allocates `Array(repeating: UInt8(0), count: 50 * 1024 * 1024)` (50 MB), keeps a strong reference, captures `after`. Asserts `after >= before` (loose because of compressed memory; strict equality NOT required).
4. Create `Tests/SwiftVoxAltaTests/Telemetry/EstimateModelMemoryTests.swift` using `@testable import SwiftVoxAlta`. Add a non-throwing internal seam `internal func _setCurrentModelRepoForTesting(_ repo: String?)` in `VoxAltaModelManager` (also part of this sortie) that simply assigns to `_currentModelRepo`. The test:
   - Instantiates `VoxAltaModelManager`, asserts `estimateModelMemoryUsage() == 0.0`.
   - Calls `await manager._setCurrentModelRepoForTesting("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")`, asserts `estimateModelMemoryUsage() == 3400.0`.
   - Calls `await manager._setCurrentModelRepoForTesting("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")`, asserts `estimateModelMemoryUsage() == 1200.0`.
   - Calls `await manager._setCurrentModelRepoForTesting("unknown")`, asserts `estimateModelMemoryUsage() == 0.0`.
   - Calls `await manager._setCurrentModelRepoForTesting(nil)`, asserts `estimateModelMemoryUsage() == 0.0`.
   The seam approach avoids any disk/network dependency in this test.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `git diff --name-only HEAD~1 -- Sources/SwiftVoxAlta/VoxAltaModelManager.swift` shows the file is modified.
- [ ] `grep -c "internal func estimateModelMemoryUsage" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1.
- [ ] `grep -c "public func getCurrentProcessMemory" Sources/SwiftVoxAlta/Telemetry/ProcessMemory.swift` returns 1.
- [ ] `grep -c "internal func _setCurrentModelRepoForTesting" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1.
- [ ] No call sites of `loadModel` / `unloadModel` are modified (`git diff Sources/SwiftVoxAlta/VoxAltaModelManager.swift | grep -E '^[-+]\s+(loadModel|unloadModel|cachedModel = nil|clearGPUCache)' | wc -l` returns 0).

---

## Sortie 4: Wire telemetry property + setter + capture helper

**Priority**: 15.35 — dependency_depth=4 (5, 6, 7, 8 use the wiring), foundation_score=1, risk=1, complexity=0.7.

**Agent**: Supervising agent.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met.
- [ ] Sortie 3 exit criteria met (must run after Sortie 3 because both modify `VoxAltaModelManager.swift`; Sortie 3 runs first per priority order).

**Tasks**:
1. In `VoxAltaModelManager`, add: `private var telemetry: (any VoxAltaTelemetryReporter)?` and `public func setTelemetry(_ reporter: (any VoxAltaTelemetryReporter)?)` that assigns to it. Place in a new `// MARK: - Telemetry` section near the bottom of the actor.
2. In `VoxAltaModelManager`, add an internal helper `internal func capture(_ event: VoxAltaTelemetryEvent) async { await telemetry?.capture(event) }`. **This helper is used by Sortie 6 to emit cache events without the cache or provider needing its own telemetry reference.** A nil reporter is a no-op and never blocks the caller.
3. **`VoxAltaVoiceProvider` is `final class @unchecked Sendable`, NOT an actor.** Add `public func setTelemetry(_ reporter: (any VoxAltaTelemetryReporter)?) async` to it that calls `await modelManager.setTelemetry(reporter)`. Also expose an `internal func capture(_ event: VoxAltaTelemetryEvent) async` that calls `await modelManager.capture(event)` — Sortie 6's cache events route through this.
4. Create `Tests/SwiftVoxAltaTests/Telemetry/SetTelemetryTests.swift`:
   - `testSetTelemetryProducesNoEvents`: instantiate provider, instantiate `MockTelemetryReporter`, call `await provider.setTelemetry(reporter)`, then `await reporter.events.isEmpty` must be `true`.
   - `testSetTelemetryNilDoesNotCrash`: same as above but pass `nil`. Asserts no crash.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `grep -c "func setTelemetry" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift` returns 1.
- [ ] `grep -c "func setTelemetry" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1.
- [ ] `grep -c "internal func capture" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1.
- [ ] `SetTelemetryTests` passes (specifically: `testSetTelemetryProducesNoEvents` confirms the setter alone does not emit events).

---

## Sortie 5: Instrument loadModel and unloadModel

**Priority**: 8.75 — dependency_depth=2, foundation_score=0, risk=2 (lifecycle change in actor), complexity=1.5.

**Agent**: Supervising agent (build-heavy and modifies `VoxAltaModelManager.swift`).

**Entry criteria**:
- [ ] Sortie 3 exit criteria met (helpers exist).
- [ ] Sortie 4 exit criteria met (`telemetry` property and `capture` helper exist).

**Tasks**:
1. In `VoxAltaModelManager.loadModel(repo:)`, capture `await capture(.modelLoadStart(repo: repo, cacheHit: cachedModel != nil))` as the **first statement** of the function body. After a successful return path (immediately before `return cached` for the cache-hit branch, and before `return model` for the fresh-load branch), capture `await capture(.modelLoadComplete(repo: repo, sizeMB: estimateModelMemoryUsage()))`. The error path does NOT emit a complete event (matches load-then-throw semantics).
2. In `VoxAltaModelManager.unloadModel()`:
   - Before mutation, compute `let wasLoaded = cachedModel != nil; let preSizeMB = estimateModelMemoryUsage(); let memBefore = getCurrentProcessMemory()`.
   - Capture `await capture(.modelUnloadStart(loaded: wasLoaded, sizeMB: preSizeMB))`.
   - Run the existing unload logic (`cachedModel = nil; _currentModelRepo = nil; await MemoryManager.shared.clearGPUCache()`).
   - After clearGPUCache, capture `let memAfter = getCurrentProcessMemory(); let freed = max(0.0, memBefore - memAfter)`.
   - Capture `await capture(.modelUnloadComplete(freed: freed, processMemoryMB: memAfter))`. **`freed ≈ 0` while `preSizeMB > 0` is the leak signal Produciesta is looking for. Cross-reference with Sortie 1's probe verdict.**
3. Verify all telemetry calls go through the new `capture(_:)` helper from Sortie 4; do not introduce direct `telemetry?.capture(...)` calls in this sortie. (This keeps the nil-safe forwarding centralized.)
4. Create `Tests/SwiftVoxAltaTests/Telemetry/LoadUnloadTelemetryTests.swift`:
   - `testLoadModelEmitsStartAndComplete`: attach a `MockTelemetryReporter`, call `_loadModelDiscardingResult(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")` wrapped in `do/catch` (the load may throw if the model isn't on disk — expected). Assert the recorded events START with `.modelLoadStart(repo:cacheHit: false)`. The complete event may or may not fire depending on whether the load reaches the success path; the test asserts only the start event ordering.
   - `testUnloadModelEmitsStartAndComplete`: with a `MockTelemetryReporter` attached, call `await manager.unloadModel()` directly (it's a no-op when no model is loaded but still emits events). Assert the recorded events are exactly `[.modelUnloadStart(loaded: false, sizeMB: 0.0), .modelUnloadComplete(freed: <Double>, processMemoryMB: <Double>)]` using value-tolerant matchers for the two `Double` fields.
   - `testTelemetryNilIsNoOp`: call `loadModel`/`unloadModel` without setting telemetry; assert no crash.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `LoadUnloadTelemetryTests` records exactly the documented event sequences.
- [ ] **No regression** in pre-existing unit test count: capture `make test-unit 2>&1 | grep -E "^Test Suite.*(passed|failed)"` count before this sortie's diff is applied vs after; failed-count must not increase.
- [ ] `grep -c "max(0.0, memBefore - memAfter)" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 1 (verifies the deterministic freed-formula is in place).

---

## Sortie 6: Voice cache reportState + growth events

**Priority**: 5.5 — dependency_depth=1 (only Sortie 8), foundation_score=0, risk=2, complexity=1.0.

**Agent**: **Sub-agent eligible** — code/test writing only. The supervising agent runs `make build` and `make test-unit` after handoff. **Important: the sub-agent must NOT invoke any build commands.**

**Entry criteria**:
- [ ] Sortie 2 exit criteria met (`VoiceCacheTelemetry` and `TopVoice` exist).
- [ ] Sortie 4 exit criteria met (provider has `capture` helper).

**Parallelizes with Sortie 5** — disjoint files: Sortie 6 modifies `VoxAltaVoiceCache.swift` and `VoxAltaVoiceProvider.swift`; Sortie 5 modifies `VoxAltaModelManager.swift`.

**Tasks**:
1. In `VoxAltaVoiceCache`, add `public func reportState() -> VoiceCacheTelemetry`. Implementation:
   - `entriesCount = voices.count`
   - `totalBytesCached = voices.values.map { $0.clonePromptData.count }.reduce(0, +)`
   - `topVoicesBySize` = `voices.map { TopVoice(voiceId: $0.key, bytes: $0.value.clonePromptData.count) }.sorted(by: { $0.bytes > $1.bytes }).prefix(5).map { $0 }`
   - Return `VoiceCacheTelemetry(entriesCount:, totalBytesCached:, topVoicesBySize:)`.
2. The cache's existing public mutation methods in `VoxAltaVoiceCache` are `store(id:data:gender:)`, `remove(id:)`, `removeAll()`. **Do not** instrument the cache directly — keep it telemetry-free. Instead, in `VoxAltaVoiceProvider`, after each existing call site that mutates the cache (`loadVoice` calls `voiceCache.store`; `unloadVoice` calls `voiceCache.remove`; `unloadAllVoices` calls `voiceCache.removeAll`), add immediately after the mutation:
   ```swift
   let state = await voiceCache.reportState()
   let totalMB = Double(state.totalBytesCached) / (1024.0 * 1024.0)
   await capture(.voiceCacheGrowth(entriesCount: state.entriesCount, totalMB: totalMB))
   ```
   Use the `capture(_:)` helper added in Sortie 4 (which forwards to `modelManager.capture`). **Do not** instrument `storeClonePrompt` (internal hot-path machinery; not a growth event).
3. Create `Tests/SwiftVoxAltaTests/Telemetry/VoiceCacheReportTests.swift`:
   - `testReportStateMatchesInsertedData`: insert 3 voices with `Data` payloads of sizes 100, 200, 300 bytes via `cache.store(id:data:gender:)`. Call `reportState()`. Assert `entriesCount == 3`, `totalBytesCached == 600`, `topVoicesBySize.first?.bytes == 300`.
   - `testTopVoicesBySizeLimit`: insert 7 voices. Assert `topVoicesBySize.count == 5`.
   - `testProviderEmitsGrowthOnLoadVoice`: instantiate provider, attach `MockTelemetryReporter`, call `await provider.loadVoice(id: "TEST", clonePromptData: Data(repeating: 0, count: 1024))`. Assert at least one captured event matches `.voiceCacheGrowth(entriesCount: 1, totalMB: <Double>)`.
   - `testProviderEmitsGrowthOnUnload`: extends the previous test by calling `await provider.unloadVoice(id: "TEST")`; assert a second `.voiceCacheGrowth(entriesCount: 0, totalMB: 0.0)` event fires.

**Exit criteria** (verified by supervising agent post-handoff):
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `grep -c "public func reportState" Sources/SwiftVoxAlta/VoxAltaVoiceCache.swift` returns 1.
- [ ] `grep -c "voiceCacheGrowth" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift` returns 3 (one per mutation site: `loadVoice`, `unloadVoice`, `unloadAllVoices`).
- [ ] `git diff --name-only HEAD~1 -- Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns no output (this sortie does NOT modify the manager — that's Sortie 5's domain).

---

## Sortie 7: MLX retention + Metal buffer probe (best-effort)

**Priority**: 6.65 — dependency_depth=1, foundation_score=0, risk=3 (unknown external API surface), complexity=1.3.

**Agent**: Supervising agent (build + research; modifies `VoxAltaModelManager.swift`).

**Entry criteria**:
- [ ] Sortie 2 exit criteria met (`MLXRetentionReport` exists).
- [ ] Sortie 5 exit criteria met (load/unload instrumented — this sortie inserts events around those instrumentation points).

**Tasks**:
1. Probe the public API surface available from the imported `MLX` and `MLXAudioTTS` modules. Allowed methods:
   - Read `Package.swift` to confirm the mlx-swift dependency identifier.
   - Run `xcodebuild -showBuildSettings -scheme SwiftVoxAlta-Package -destination 'platform=macOS,arch=arm64' | grep -i SOURCE_ROOT` to locate dependency sources.
   - `grep -R "public " ~/Library/Developer/Xcode/DerivedData/SwiftVoxAlta-*/SourcePackages/checkouts/mlx-swift/Source/MLX/Stream/ ~/Library/Developer/Xcode/DerivedData/SwiftVoxAlta-*/SourcePackages/checkouts/mlx-swift/Source/Cmlx/ 2>/dev/null` to inventory public symbols.
   - **Forbidden**: `@_implementationOnly`, `_internal`, reflection on private fields, swizzling.
2. Implement `private func checkMLXRetention() -> MLXRetentionReport` on `VoxAltaModelManager`. For each field:
   - `activeArrayCount`: if a public counter is reachable, use it; else `-1`.
   - `metalHeapSizeMB`: if `MLX.GPU.activeMemory` (or equivalent public symbol) is reachable, divide by `1024*1024` and store; else `-1`.
   - `modelRegistrySize`: SwiftVoxAlta does not maintain a model registry; return `-1` and document this in a code comment.
   - **If no fields are reachable, return `MLXRetentionReport(activeArrayCount: -1, metalHeapSizeMB: -1.0, modelRegistrySize: -1)`. The sortie still ships.**
3. In the `loadModel` success path, immediately after the existing `.modelLoadComplete` capture (added in Sortie 5), add:
   ```swift
   let mlxReport = checkMLXRetention()
   await capture(.metalBufferState(allocatedMB: mlxReport.metalHeapSizeMB, peakMB: -1.0))
   ```
   Add the same pattern in `unloadModel` after the existing `.modelUnloadComplete` capture. **`peakMB: -1.0` is intentional — we have no reachable peak counter; document this on the call site with a single-line `// peak unavailable from public MLX API` comment.**
4. Create `Tests/SwiftVoxAltaTests/Telemetry/MLXRetentionTests.swift`:
   - `testCheckMLXRetentionDoesNotCrash`: call `checkMLXRetention()` via `@testable import` seam (add `internal func _checkMLXRetentionForTesting() -> MLXRetentionReport { checkMLXRetention() }`). Assert it returns a struct (no crash). Tolerate `-1` values.
   - `testMetalBufferStateFiresAroundLoadUnload`: attach `MockTelemetryReporter`, call `unloadModel()` (no-op path). Assert exactly one `.metalBufferState` event is captured (the post-unload one — load events only fire if a load succeeds). The load+unload symmetry is verified in Sortie 8's E2E test where mocking is broader.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `grep -RE "@_implementationOnly|_internal" Sources/SwiftVoxAlta/Telemetry/ Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns no output (no private API usage).
- [ ] `grep -c "metalBufferState" Sources/SwiftVoxAlta/VoxAltaModelManager.swift` returns 2 (one in load, one in unload).
- [ ] `MLXRetentionTests` passes; the `testCheckMLXRetentionDoesNotCrash` test asserts no crash regardless of `-1` values.

---

## Sortie 8: End-to-end protocol contract test + docs

**Priority**: 1.5 — dependency_depth=0 (terminal sortie), foundation_score=0, risk=1, complexity=1.0.

**Agent**: Supervising agent (final verification).

**Entry criteria**:
- [ ] Sorties 5, 6, 7 exit criteria met.

**Tasks**:
1. Create `Tests/SwiftVoxAltaTests/Telemetry/EndToEndContractTests.swift`. Define a small adapter struct in the test file that wraps `MockTelemetryReporter` and exposes `var capturedEvents: [VoxAltaTelemetryEvent] { get async }`. Test `testProduciestaContractEventStream`:
   - Instantiate a `VoxAltaVoiceProvider`, attach the adapter via `setTelemetry`.
   - Call `await provider.loadVoice(id: "TEST_E2E", clonePromptData: Data(repeating: 0xAB, count: 2048))`.
   - Call `await provider.unloadAllVoices()`.
   - **Do not** call `generateAudio` or any method that triggers actual model loading (would require disk model + 3.4GB).
   - Assert the captured event stream contains, in order, exactly these event types (use `case` matching, not value equality, for `Double`-bearing fields):
     1. `.voiceCacheGrowth` (entriesCount: 1)
     2. `.voiceCacheGrowth` (entriesCount: 0)
   - Then exercise `unloadModel()` directly on the manager (it's a no-op without a loaded model but still fires telemetry):
     - Assert these events appear in order: `.modelUnloadStart(loaded: false, sizeMB: 0.0)`, `.modelUnloadComplete(freed: <Double>, processMemoryMB: <Double>)`, `.metalBufferState(allocatedMB: <Double>, peakMB: -1.0)`.
   - **Note**: the original requirements doc shows a stringified format (`📊 [VoxAlta] Model load start...`); this test asserts the typed enum stream that produces that string format. The enum is the contract; the string format is a downstream concern of Produciesta's adapter.
2. Create `docs/telemetry.md` (the project already has a `docs/` directory). Sections required:
   - **Public API**: list `VoxAltaTelemetryEvent` (all six cases), `VoxAltaTelemetryReporter`, `VoiceCacheTelemetry`, `MLXRetentionReport`, `getCurrentProcessMemory`. Reference each by exact name.
   - **How to attach a reporter from Produciesta**: code snippet showing `let provider = VoxAltaVoiceProvider(); await provider.setTelemetry(MyReporter())`.
   - **Preflight Probe**: short subsection pointing to `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift` and the `VOXALTA_RUN_LEAK_PROBE=1` invocation. Include the latest verdict from `LEAK_PROBE_RESULT.md` (read at sortie execution time).
   - **Known limitation**: `freed` may be near 0 even after `unloadModel()` returns when `mlx-swift` retains the model — this is the bug the instrumentation exists to surface, not a defect in the telemetry pipeline.
   - **Known limitation**: `metalBufferState.peakMB` is always `-1.0` because the public mlx-swift API does not expose a peak counter.
3. Add a one-paragraph entry under a new `## Telemetry` heading in `AGENTS.md` linking to `docs/telemetry.md` and naming the public types.
4. Run `make test-unit` — full suite (`make test`) is **not** required because `make test-integration` depends on a 3.4GB cached model and adds no signal for telemetry-only changes. The git-diff scope check below confirms only telemetry files were touched.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0.
- [ ] `EndToEndContractTests.testProduciestaContractEventStream` passes and matches the documented event sequence above.
- [ ] `test -f docs/telemetry.md` returns 0.
- [ ] `grep -c "VoxAltaTelemetryEvent" docs/telemetry.md` returns ≥ 1; same for `VoxAltaTelemetryReporter`, `VoiceCacheTelemetry`, `MLXRetentionReport`, `getCurrentProcessMemory`.
- [ ] `grep -c "PreflightLeakProbeTests" docs/telemetry.md` returns ≥ 1.
- [ ] `grep -c "## Telemetry" AGENTS.md` returns ≥ 1; the section links to `docs/telemetry.md`.
- [ ] `git diff --stat HEAD~7 HEAD -- Sources/` shows only `Sources/SwiftVoxAlta/Telemetry/*` (new), `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`, `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`, `Sources/SwiftVoxAlta/VoxAltaVoiceCache.swift` (modified) — no other source files changed.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 8 (1 preflight probe + 7 implementation) |
| Dependency structure | Layered (1 → 2 → {3 then 4 sequential due to file conflict} → {5 ‖ 6 parallel} → 7 → 8) |
| Critical path | 6 sorties (1 → 2 → 4 → 5 → 7 → 8) |
| Maximum parallelism | 2 agents (1 supervising + 1 sub-agent during Group 3) |
| New source files | 4 (`Sources/SwiftVoxAlta/Telemetry/{VoxAltaTelemetryEvent,VoxAltaTelemetryReporter,VoxAltaTelemetryTypes,ProcessMemory}.swift`) |
| Modified source files | 3 (`VoxAltaModelManager`, `VoxAltaVoiceProvider`, `VoxAltaVoiceCache`) |
| New test files | 8 (1 probe + 7 telemetry) |
| New documentation files | 1 (`docs/telemetry.md`) |
| Mission artifacts at root | `LEAK_PROBE_RESULT.md`, `LEAK_PROBE_XCODEBUILD.log`, `EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md` (auto-archived by `clean` post-mission) |
| Average sortie size | ~22 turns (budget: 50) — all sorties right-sized, no splits/merges needed |
| Estimated wall-clock | Sortie 1: ~2 min (real model load+unload). Sorties 2–8: ~30–60 min total assuming sub-agent parallelism on Group 3. |

---

## Out of Scope (explicit)

- Fixing the leak. This mission **proves** whether `unloadModel()` works (Sortie 1 empirically; Sorties 2–8 instrument for production observability); remediation is a separate mission.
- Modifying Produciesta. The contract is protocol-only; integration lives in the consumer repo.
- Building a generic profiler. We only instrument the points named in the requirements.
- Touching mlx-swift internals. If a value isn't exposed publicly, we report `-1`.
- Running `make test-integration` (full integration suite). Telemetry-only changes don't affect audio generation, and the suite needs a 3.4GB cached model. The diff-scope assertion in Sortie 8 is the equivalent confidence check. (Note: Sortie 1 DOES load a real model, but invokes `xcodebuild test` directly with `-only-testing`, not `make test-integration`.)
- Multi-cycle leak amplification (3+ load/unload cycles to detect cumulative growth). Sortie 1 does a single cycle. If verdict is INCONCLUSIVE, the user can manually request a multi-cycle re-run before resuming the mission.

## Known Risks

- **Sortie 1 timing sensitivity**: `task_info` resident_size may not reflect MLX-async deallocation that completes after the 500 ms drain window. If the verdict is `INCONCLUSIVE`, increase the drain to 2 s and re-run before treating it as a real signal.
- **Async/actor reentrancy**: `VoxAltaModelManager` **is** an actor (confirmed at `VoxAltaModelManager.swift:201`). Calling `await capture(...)` from inside `loadModel`/`unloadModel` introduces reentrancy points. Sortie 5's no-regression check in exit criteria guards against ordering-dependent test failures. If a regression appears, the supervisor falls back to wrapping captures in `Task { ... }` to detach them from the critical path.
- **`getCurrentProcessMemory()` accuracy**: `mach_task_basic_info.resident_size` is approximate, includes shared memory, and is affected by macOS's compressed-memory subsystem. Useful for **deltas**, not absolutes. Documented in the helper's doc comment (Sortie 3 task 2) and again in `docs/telemetry.md` (Sortie 8 task 2).
- **MLX public API drift**: Sortie 7 depends on whatever the forked mlx-audio-swift / mlx-swift expose **today**. Auto-fix in Pass 4 already absorbs this risk: any unreachable value defaults to `-1` and the sortie still ships. The `metalBufferState` event still fires regardless.
- **Sortie 6 sub-agent handoff**: The sub-agent must not run `make build`. If the sub-agent inadvertently invokes a build command, results may differ from the supervising agent's environment (Metal shader compilation is sensitive). Mitigation: the sortie spec explicitly forbids build invocation; the supervising agent re-runs the build after handoff.
- **Probe-vs-instrument divergence**: It's possible Sortie 1 says NO LEAK while Produciesta still observes a leak. This means the leak emerges only across multi-component state (Produciesta's `VoxAltaTelemetryAdapter`, voice cache patterns over multiple episodes, retain cycles in callback closures, etc.). The mission is still valuable in this case — it gives Produciesta the hooks to find the real bug — but the user should know the suspect has shifted.

## Open Questions & Missing Documentation

All Pass 4 issues from the original refinement were auto-fixed. **No blocking open questions remain.**

| Pre-refinement issue | Severity | Resolution applied |
|----------------------|----------|---------------------|
| Sortie 3: vague "test seam" | Medium | Added concrete `_setCurrentModelRepoForTesting` seam |
| Sortie 4: claimed provider was an actor | Medium | Corrected — provider is `final class @unchecked Sendable`; `setTelemetry` is `async` and forwards |
| Sortie 5: non-deterministic `freed` formula | High | Replaced with `freed = max(0.0, memBefore - memAfter)` |
| Sortie 5: required `make test` (full integration) | High | Replaced with `make test-unit` (no model dependency) |
| Sortie 6: vague "every cache mutation site" | Medium | Listed exact provider call sites: `loadVoice`, `unloadVoice`, `unloadAllVoices` |
| Sortie 7: open-ended MLX API research | Medium | Documented allowed probing methods + `-1` fallback policy |
| Sortie 8: required full `make test` | High | Replaced with `make test-unit` + git-diff scope check |
| Sortie 8: tested string format from requirements doc | Medium | Re-anchored to typed enum cases — string format is Produciesta's concern |
| Mission premise unverified | High (added in this revision) | New Sortie 1 empirically tests the leak before any instrumentation work begins |

**Verdict**: Plan is ready to execute. Next step: `/mission-supervisor start /Users/stovak/Projects/SwiftVoxAlta-telemetry/EXECUTION_PLAN.md`.
