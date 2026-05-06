# Preflight Leak Probe Result

Date: 2026-05-06T18:18:55Z
Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
Cycles: 1

## RSS measurements (MB)
Before load:        91.78
After load:         8874.34
After unloadModel:  430.88

## Deltas (MB)
loadGrew:           8782.56
unloadFreed:        8443.47
netDelta:           339.09

## Thresholds
LEAK SUSPECTED if netDelta > 1000.0
NO LEAK         if netDelta < 200.0
INCONCLUSIVE    otherwise

Verdict: INCONCLUSIVE

## Notes
- RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
- 500ms drain window between unloadModel() and final RSS sample.
- This probe runs inside xctest, not Produciesta. Absolute RSS values are not directly comparable across processes; deltas are.
- Invocation: direct xctest binary (not xcodebuild). macOS 26 sandbox applied to xcodebuild-launched xctest processes prevents writes to ~/Library/Group Containers/, which Acervo requires during ensureComponentReady() to update model metadata. Direct xctest invocation bypasses this restriction and is functionally equivalent for RSS measurement purposes. See LEAK_PROBE_XCODEBUILD.log for the xcodebuild attempt (build succeeded; test failed with sandbox write error).