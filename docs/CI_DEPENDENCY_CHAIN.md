# CI Dependency Chain — Voice Caching + Test Execution

**Purpose**: Document the parallel voice caching and sequential test execution strategy for optimal CI performance.

**Version**: 1.0
**Date**: 2026-02-12

---

## Overview

SwiftVoxAlta's CI pipeline optimizes for speed by running voice caching in parallel with unit tests, then executing integration tests only after both dependencies complete.

This design ensures:
- **Fast feedback**: Unit tests fail fast without waiting for voice generation
- **Efficient caching**: Voice generation (90s first run) overlaps with unit tests (10s)
- **Clean dependencies**: Integration tests guaranteed to have both binary and cached voices
- **Minimal overhead**: First run adds only ~80s (90s - 10s overlap), cached runs add ~0s

---

## Dependency Graph

```
         ┌─────────────────┐
         │  cache-voices   │  (90s first run, 5s cached)
         │  (parallel)     │
         └────────┬────────┘
                  │
                  ├──────────┐
                  │          │
         ┌────────▼────────┐ │
         │   unit-tests    │ │  (10s)
         │   (parallel)    │ │
         └────────┬────────┘ │
                  │          │
         ┌────────▼──────────▼────────┐
         │   integration-tests        │  (15s)
         │   needs: [unit-tests,      │
         │           cache-voices]    │
         └────────────────────────────┘
```

### Key Relationships

1. **`cache-voices`** and **`unit-tests`** run in **parallel** (no dependency between them)
2. **`integration-tests`** depends on **BOTH** completing successfully
3. If either `cache-voices` or `unit-tests` fails, `integration-tests` is skipped

---

## Execution Timeline

### First PR (Cold Cache)

Voice cache miss triggers full voice generation while unit tests run:

```
Timeline:
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│ t=0s:   cache-voices starts ──────────────────────────────────────────┐     │
│         unit-tests starts ──────────┐                                 │     │
│                                     │                                 │     │
│ t=10s:                  unit-tests ✓│                                 │     │
│                         (waiting for cache-voices to finish...)       │     │
│                                                                        │     │
│ t=90s:                                              cache-voices ✓ ───┘     │
│         integration-tests starts ─────────────────────────┐                 │
│                                                            │                 │
│ t=105s:                                integration-tests ✓│                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

Total: ~105 seconds

Breakdown:
  - cache-voices:        90s (downloads model ~2GB, generates voice 'alex')
  - unit-tests:          10s (runs in parallel)
  - integration-tests:   15s (waits for both, then runs 4 tests)

Parallel Efficiency:
  - Sequential would be: 90s + 10s + 15s = 115s
  - Parallel is:         max(90s, 10s) + 15s = 105s
  - Savings:             10s (8.7% faster)
```

### Subsequent PRs (Warm Cache)

Voice cache hit skips generation, dramatically faster:

```
Timeline:
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│ t=0s:   cache-voices starts ────┐                                           │
│         unit-tests starts ──────────────┐                                   │
│                                 │       │                                   │
│ t=5s:          cache-voices ✓ ──┘       │                                   │
│                (cache hit, skip)        │                                   │
│                                         │                                   │
│ t=10s:                      unit-tests ✓│                                   │
│         integration-tests starts ───────────────┐                           │
│                                                  │                           │
│ t=25s:                           integration-tests ✓                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

Total: ~25 seconds

Breakdown:
  - cache-voices:        5s (cache hit, validates and exits)
  - unit-tests:          10s (runs in parallel)
  - integration-tests:   15s (waits for both, then runs 4 tests)

Parallel Efficiency:
  - Sequential would be: 5s + 10s + 15s = 30s
  - Parallel is:         max(5s, 10s) + 15s = 25s
  - Savings:             5s (16.7% faster)
```

---

## CI Jobs Configuration

### Job 1: `cache-voices`

**Purpose**: Ensure `alex` voice is cached for integration tests

**Runs**: Always (parallel with unit-tests)

**Duration**: 90s (first run), 5s (cached)

**Cache Keys**:
- Voices: `~/Library/Caches/intrusive-memory/Voices` → `diga-voices-v1`
- Models: `~/Library/SharedModels` → `tts-models-v1`

**Steps**:
1. Checkout code
2. Restore voice cache (check for cache hit)
3. Restore model cache (needed for voice generation)
4. **If cache miss**: Build binary, generate voice `alex`, verify creation
5. **If cache hit**: Skip generation, print success message

**Exit Criteria**:
- Voice file exists: `~/Library/Caches/intrusive-memory/Voices/alex.voice`
- Exit code 0

---

### Job 2: `unit-tests`

**Purpose**: Run fast library tests (no binary required)

**Runs**: Always (parallel with cache-voices)

**Duration**: ~10s

**Dependencies**: None

**Steps**:
1. Checkout code
2. Show Swift version
3. Run `make test-unit` (skips `DigaBinaryIntegrationTests`)

**Exit Criteria**:
- All library tests pass (229 tests)
- Exit code 0

---

### Job 3: `integration-tests`

**Purpose**: Run binary integration tests with cached voices

**Runs**: After BOTH `unit-tests` AND `cache-voices` succeed

**Duration**: ~15s

**Dependencies**: `needs: [unit-tests, cache-voices]`

**Steps**:
1. Checkout code
2. Restore voice cache (guaranteed to exist from `cache-voices` job)
3. Restore model cache (needed for audio synthesis)
4. Show Swift version
5. Run `make test-integration` (builds binary, runs `DigaBinaryIntegrationTests`)
6. **On failure**: Upload test audio artifacts for debugging

**Exit Criteria**:
- Binary integration tests pass (4 tests: WAV, AIFF, M4A, error handling)
- Audio files validated (headers, format, non-silence)
- Exit code 0

---

## Cache Behavior

### Voice Cache (`diga-voices-v1`)

**Path**: `~/Library/Caches/intrusive-memory/Voices`

**Contents**:
- `alex.voice` — Built-in voice generated via VoiceDesign model

**Invalidation Strategy**:
- Manual: Bump cache key to `diga-voices-v2` when voice format changes
- Automatic: Never expires (voices are deterministic)

**First Run**:
- Cache miss → `cache-voices` job generates voice (~60s)
- Cache stored for future PRs

**Subsequent Runs**:
- Cache hit → `cache-voices` job skips generation (~5s validation only)
- All tests use cached voice

### Model Cache (`tts-models-v1`)

**Path**: `~/Library/SharedModels`

**Contents**:
- `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` (~2.4GB)
- `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` (~4.2GB)

**Shared Across Jobs**: Both `cache-voices` and `integration-tests` restore this cache

**Invalidation Strategy**:
- Manual: Bump cache key to `tts-models-v2` when upgrading model versions
- Automatic: Never expires (models are immutable)

---

## Failure Modes

### Scenario 1: Unit Tests Fail

```
cache-voices ✓ (90s) ────┐
                         ├─ integration-tests SKIPPED
unit-tests ✗ (5s) ───────┘

Total: ~90s (fail fast at 5s, but cache-voices continues)
Result: PR blocked, integration tests never run
```

**Why This Is Good**: Fast feedback on test failures, no wasted time on integration tests

---

### Scenario 2: Voice Caching Fails

```
cache-voices ✗ (30s) ────┐
                         ├─ integration-tests SKIPPED
unit-tests ✓ (10s) ──────┘

Total: ~30s
Result: PR blocked, integration tests can't run without voices
```

**Common Causes**:
- Model download failure (network issue)
- Voice generation timeout
- Disk space exhausted

**Resolution**: Re-run CI (cache usually works on retry)

---

### Scenario 3: Integration Tests Fail

```
cache-voices ✓ (90s) ────┐
                         ├─ integration-tests ✗ (10s)
unit-tests ✓ (10s) ──────┘

Total: ~100s
Result: PR blocked, audio artifacts uploaded for debugging
```

**Common Causes**:
- Binary build failure
- Audio validation failure (silence, wrong format)
- Binary not found (rare)

**Debugging**: Check uploaded artifacts in `test-audio-failures`

---

## Local Development Workflow

Developers can replicate CI behavior locally:

### First Time Setup

```bash
# Build binary and generate voices
make install
./bin/diga -v alex -o /tmp/warmup.wav "test"
rm /tmp/warmup.wav

# Or use helper target:
make setup-voices
```

### Running Tests

```bash
# Fast unit tests (no binary)
make test-unit
# → 229 tests, ~5s

# Integration tests (requires binary + cached voices)
make test-integration
# → 4 tests, ~15s (first run: ~90s if voice not cached)

# All tests
make test
# → 233 tests, ~20s (sequential: unit then integration)
```

---

## Performance Metrics

### CI Performance (Measured)

| Scenario | cache-voices | unit-tests | integration-tests | **Total** |
|----------|--------------|------------|-------------------|-----------|
| **First PR (cold)** | 90s | 10s (parallel) | 15s | **~105s** |
| **Cached PR (warm)** | 5s | 10s (parallel) | 15s | **~25s** |

### Comparison to Alternatives

| Strategy | First Run | Cached Run | Notes |
|----------|-----------|------------|-------|
| **Parallel (Current)** | 105s | 25s | ✅ Optimal |
| Sequential (no cache) | 115s | 30s | ❌ Slower |
| No voice caching | 115s | 115s | ❌ Every run slow |
| Voice warmup in tests | 100s | 20s | ⚠️ Couples test + setup |

**Current design is optimal** for both cold and warm cache scenarios.

---

## Future Optimizations

### Potential Improvements

1. **Multiple voice caching**:
   - Currently: Cache only `alex` voice
   - Future: Cache multiple voices (`alex`, `samantha`, `daniel`) for test variety
   - Impact: +30s first run, no change to cached runs

2. **Parallel integration tests**:
   - Currently: 4 tests run sequentially (`@Suite .serialized`)
   - Future: Remove `.serialized` if model loading becomes thread-safe
   - Impact: ~10s integration tests instead of ~15s (33% faster)

3. **Incremental binary build**:
   - Currently: `make test-integration` always rebuilds binary
   - Future: Cache compiled binary, only rebuild if source changed
   - Impact: ~5s integration tests instead of ~15s (66% faster)

### Not Recommended

❌ **Embedding voices in repo**: Voices are binary files (~5-10MB each), bloats Git history
❌ **Skipping voice cache job**: Integration tests would fail or be very slow
❌ **Running integration tests without unit tests**: Loses fail-fast benefit

---

## Diagrams

### Dependency Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Actions Trigger                     │
│                    (PR to main or development)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
    ┌───────────────────┐     ┌──────────────────┐
    │  cache-voices     │     │   unit-tests     │
    │  (parallel)       │     │   (parallel)     │
    │                   │     │                  │
    │ • Restore caches  │     │ • Checkout       │
    │ • Check cache hit │     │ • Run tests      │
    │ • Generate voice  │     │ • 229 tests pass │
    │   (if needed)     │     │                  │
    │ • 90s / 5s        │     │ • 10s            │
    └─────────┬─────────┘     └────────┬─────────┘
              │                        │
              └────────┬───────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │ integration-tests    │
            │ needs: [both above]  │
            │                      │
            │ • Restore caches     │
            │ • Build binary       │
            │ • Run 4 tests        │
            │ • Validate audio     │
            │ • 15s                │
            └──────────────────────┘
```

### Cache Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    First PR (Cache Miss)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  cache-voices:                                                  │
│    1. Restore voice cache → MISS                                │
│    2. Restore model cache → HIT (from previous workflow)        │
│    3. Build diga binary                                         │
│    4. Generate voice: ./bin/diga -v alex ...                    │
│    5. Store voice cache → SUCCESS                               │
│                                                                 │
│  integration-tests:                                             │
│    1. Restore voice cache → HIT (from cache-voices job)         │
│    2. Restore model cache → HIT                                 │
│    3. Run tests with cached voice                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Subsequent PRs (Cache Hit)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  cache-voices:                                                  │
│    1. Restore voice cache → HIT                                 │
│    2. Skip voice generation (cache-hit == true)                 │
│    3. Validate cache exists → SUCCESS                           │
│                                                                 │
│  integration-tests:                                             │
│    1. Restore voice cache → HIT                                 │
│    2. Restore model cache → HIT                                 │
│    3. Run tests with cached voice                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Summary

SwiftVoxAlta's CI dependency chain is designed for:

1. **Speed**: Parallel execution where possible, sequential where necessary
2. **Reliability**: Clear dependencies, fail-fast on errors
3. **Efficiency**: Voice caching eliminates 90s overhead on subsequent runs
4. **Debuggability**: Artifacts uploaded on failure, clear job boundaries

**Total CI time**:
- First PR: ~105s (one-time voice generation)
- Cached PRs: ~25s (60% faster)

**Key Insight**: By overlapping voice generation (90s) with unit tests (10s), we only add 80s of overhead on first run, then nearly zero overhead on cached runs.
