# Telemetry

SwiftVoxAlta exposes a pluggable telemetry pipeline for consumers (Produciesta and others) to observe model lifecycle and voice-cache state in production. The telemetry surface is a protocol-only contract — SwiftVoxAlta emits events; consumers implement how to log, aggregate, or alert on them.

> **Status note**: This pipeline was originally scoped to investigate whether `unloadModel()` was leaking memory across episodes. An empirical 3-cycle preflight probe (see [Preflight Probe](#preflight-probe) below) **falsified that hypothesis** — `unloadModel()` reliably reclaims ~96% of the loaded model's resident memory; the residual ~340 MB is one-time MLX/Metal framework setup cost (not progressive). The telemetry remains as **observability infrastructure** for consumers to verify behavior in production and surface future regressions, not as a leak-hunting tool.

## Public API

| Type | File | Purpose |
|------|------|---------|
| `VoxAltaTelemetryEvent` | `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` | Six-case enum: lifecycle events emitted by the manager and provider. |
| `VoxAltaTelemetryReporter` | `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryReporter.swift` | Async protocol consumers implement to receive events. |
| `VoiceCacheTelemetry` (with nested `TopVoice`) | `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryTypes.swift` | Snapshot of voice-cache state: entries count, total bytes, top 5 voices by size. |
| `MLXRetentionReport` | `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryTypes.swift` | Snapshot of MLX/Metal retention. Some fields may be `-1` when the public MLX API does not expose the underlying counter. |
| `getCurrentProcessMemory() -> Double` | `Sources/SwiftVoxAlta/Telemetry/ProcessMemory.swift` | Current process RSS in MB via `task_info`. Approximate; useful for **deltas**, not absolutes. |

### The six events

| Case | When emitted | Notes |
|------|-------------|-------|
| `.modelLoadStart(repo:cacheHit:)` | First statement of `loadModel`. | `cacheHit` is `true` if a model is already cached. |
| `.modelLoadComplete(repo:sizeMB:)` | Just before each `return` in `loadModel`. | Two emission sites (cache-hit branch + fresh-load branch). Not emitted on the error path. |
| `.modelUnloadStart(loaded:sizeMB:)` | First action in `unloadModel`. | `sizeMB` is the estimated model size before unload (0.0 if no model loaded). |
| `.modelUnloadComplete(freed:processMemoryMB:)` | After `clearGPUCache` returns. | `freed = max(0.0, memBefore - memAfter)` — deterministic non-negative. |
| `.voiceCacheGrowth(entriesCount:totalMB:)` | After each `provider.loadVoice` / `unloadVoice` / `unloadAllVoices`. | Reads `voiceCache.reportState()` and emits a snapshot. |
| `.metalBufferState(allocatedMB:peakMB:)` | After each `.modelLoadComplete` and after `.modelUnloadComplete`. | `peakMB` is always `-1.0` — see [Known Limitations](#known-limitations). |

## How to attach a reporter (Produciesta integration example)

```swift
import SwiftVoxAlta

actor MyReporter: VoxAltaTelemetryReporter {
    func capture(_ event: VoxAltaTelemetryEvent) async {
        // log to Produciesta's metrics pipeline
    }
}

let provider = VoxAltaVoiceProvider()
await provider.setTelemetry(MyReporter())
```

Pass `nil` to detach: `await provider.setTelemetry(nil)`. A nil reporter is a no-op — emission paths never block.

## Preflight Probe

`Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift` is a permanent regression test that performs a 3-cycle real model load+unload of `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` and writes a verdict to `LEAK_PROBE_RESULT.md` at the project root.

The probe is **skipped by default**. To run it:

```bash
make test-leak-probe
```

Or, if `make test-leak-probe` fails due to the macOS 26 xcodebuild sandbox issue (see below), run via direct xctest invocation. The probe gate is the env var `VOXALTA_RUN_LEAK_PROBE=1` (or a sentinel file at `/tmp/voxalta_run_leak_probe`).

**Latest verdict** (2026-05-06, 3-cycle, 2 s drain per cycle):

| Field | Value |
|-------|-------|
| d1 (cycle 1, includes one-time framework overhead) | ~340 MB |
| d2 (cycle 2 marginal) | ~19 MB |
| d3 (cycle 3 marginal) | ~5 MB |
| Marginal average (d2+d3)/2 | ~12 MB |
| Verdict | **NO LEAK** (threshold: <50 MB) |

The first-cycle ~340 MB residual is one-time MLX/Metal framework setup cost; cycles 2–3 demonstrate that `unloadModel()` reclaims everything else.

### Known limitation: macOS 26 xcodebuild sandbox

`make test-leak-probe` invokes `xcodebuild test`, but on macOS 26+ xcodebuild applies a write sandbox to xctest processes that prevents writes to `~/Library/Group Containers/<app-group-id>/`. SwiftAcervo's `ensureComponentReady()` writes model metadata to that path during model hydration, so the probe fails at the cache-write step when run via `xcodebuild test`.

Workaround: invoke the built xctest binary directly. The Makefile target's documentation block describes the exact command. This is a macOS-level restriction, not a code defect; the `.acervoEnvironment` Swift Testing trait correctly bootstraps `ACERVO_APP_GROUP_ID`, but no env var or trait can waive the kernel-level sandbox on filesystem writes.

## Known Limitations

- **`freed` may be near 0** even after `unloadModel()` returns when MLX retains model state. The 3-cycle preflight probe demonstrates this is **not** a progressive leak — the residual is one-time framework overhead. The instrumentation surfaces the actual reclamation amount; consumers can compare against the model's loaded size to detect deviations.
- **`metalBufferState.peakMB` is always `-1.0`** — the public mlx-swift API does not expose a peak counter. `allocatedMB` uses `MLX.Memory.activeMemory` and is reachable.
- **`MLXRetentionReport.activeArrayCount` and `MLXRetentionReport.modelRegistrySize` are always `-1`** — no reachable public counter for arrays; SwiftVoxAlta does not maintain a model registry.
- **`getCurrentProcessMemory()` is approximate** — `mach_task_basic_info.resident_size` includes shared memory and is affected by macOS's compressed-memory subsystem. Useful for **deltas**, not absolutes.
