# Preflight Leak Probe Result

Date: 2026-05-06T19:16:51Z
Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
Cycles: 1

## RSS measurements (MB)
Before load:        54.12
After load:         8837.98
After unloadModel:  394.52

## Deltas (MB)
loadGrew:           8783.86
unloadFreed:        8443.47
netDelta:           340.39

## Thresholds
LEAK SUSPECTED if netDelta > 1000.0
NO LEAK         if netDelta < 200.0
INCONCLUSIVE    otherwise

Verdict: INCONCLUSIVE

## Notes
- RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
- 2s drain window between unloadModel() and final RSS sample.
- This probe runs inside xctest, not Produciesta. Absolute RSS values are not directly comparable across processes; deltas are.