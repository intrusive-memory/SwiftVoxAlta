# Preflight Leak Probe Result

Date: 2026-05-06T19:26:22Z
Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
Cycles: 3
Drain per cycle: 2s

## RSS measurements (MB)
Before load:                54.47
After load (cycle 1):       8831.27
After unload (cycle 1):     394.75
After load (cycle 2):       4755.05
After unload (cycle 2):     413.45
After load (cycle 3):       4747.83
After unload (cycle 3):     418.22

## Per-cycle marginal deltas (MB)
d1 (cycle 1, includes one-time overhead):  340.28
d2 (cycle 2 marginal):                     18.70
d3 (cycle 3 marginal):                     4.77
Marginal average (d2+d3)/2:                11.73
Cumulative (3 cycles):                     363.75

## Thresholds (3-cycle, marginal-average based)
LEAK SUSPECTED if marginalAvg > 250.0
NO LEAK         if marginalAvg < 50.0
INCONCLUSIVE    otherwise

Verdict: NO LEAK

## Interpretation guide
- d1 includes one-time MLX/Metal framework setup costs that occur on first model load.
- d2 and d3 measure pure per-cycle retention. If they are near zero, the residual is structural.
- If d2 ≈ d3 ≈ d1 (~340 MB), this is a linear leak — confirmed mission premise.
- The unloadFreed magnitude (typically ~8.4 GB on this model) is NOT in the verdict — only marginal residue is.

## Notes
- RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
- 2s drain after each unload, before measuring the cycle's afterUnload RSS.
- Probe runs inside xctest, not Produciesta. Deltas are comparable; absolutes are not.
- Invocation: direct xctest binary (xcodebuild sandbox limitation on macOS 26 prevents writes to ~/Library/Group Containers/, which Acervo requires).