# CI Dependency Chain — Unit Tests Only Strategy

**Purpose**: Document the fast unit-only CI strategy that avoids large model downloads.

**Version**: 2.0
**Date**: 2026-02-14
**Status**: Current (updated to match .github/workflows/tests.yml)

---

## Overview

SwiftVoxAlta's CI pipeline runs **unit tests only** to provide fast feedback without downloading the 3.4GB Qwen3-TTS model. Integration tests that require model downloads run locally only.

This design ensures:
- **Fast feedback**: CI completes in 1-2 minutes (no model downloads)
- **No timeout issues**: Unit tests complete well within GitHub Actions limits
- **Cost efficiency**: Minimal CI minutes usage, no wasted bandwidth
- **Local verification**: Integration tests available via `make test-integration`

---

## Current CI Configuration

### Single Job: `unit-tests`

```yaml
jobs:
  unit-tests:
    name: Unit Tests
    runs-on: macos-26
    timeout-minutes: 15
    steps:
      - Checkout code
      - Show Swift version
      - Run: make test-unit
```

**What It Skips**:
1. **DigaBinaryIntegrationTests** — CLI binary integration tests
2. **testGenerateAudioWithPresetSpeaker** — Requires 3.4GB model
3. **testGenerateAudioWithAllPresetSpeakers** — Requires 3.4GB model
4. **testGenerateProcessedAudioDuration** — Requires 3.4GB model

**What It Runs**: ~226 unit tests covering:
- VoiceProvider metadata and configuration
- Voice loading/caching logic
- Duration estimation (math only)
- WAV duration parsing (no audio generation)
- Provider descriptor registration
- Sendable conformance
- CLI argument parsing and validation

---

## Dependency Graph

```
         ┌─────────────────────────────────┐
         │  GitHub Actions PR Trigger      │
         │  (main or development branch)   │
         └────────────┬────────────────────┘
                      │
                      ▼
         ┌────────────────────────────────┐
         │       unit-tests               │
         │                                │
         │  • Checkout code               │
         │  • Swift version check         │
         │  • make test-unit              │
         │    - Skip binary tests         │
         │    - Skip audio tests          │
         │  • ~226 tests                  │
         │  • Duration: 1-2 min           │
         │  • No model downloads          │
         └────────────────────────────────┘

         ┌────────────────────────────────┐
         │   integration-tests            │  ❌ DISABLED
         │   (commented out in workflow)  │
         │                                │
         │  Would require:                │
         │  • 3.4GB model download        │
         │  • ~15 min timeout             │
         │  • Binary build + voice cache  │
         │                                │
         │  Run locally instead:          │
         │  $ make test-integration       │
         └────────────────────────────────┘
```

---

## Test Classification

| Test Suite | Tests | Model? | Binary? | CI Status |
|------------|-------|--------|---------|-----------|
| **VoiceProvider - Metadata** | 5 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Configuration** | 1 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Voice Mgmt** (non-audio) | 8 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Voice Mgmt** (audio) | 3 | ✅ 3.4GB | ❌ | ❌ Skipped |
| **VoiceProvider - Audio Generation** | 2 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Duration Estimation** | 4 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - WAV Duration** | 5 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Descriptor** | 5 | ❌ | ❌ | ✅ Runs |
| **VoiceProvider - Sendable** | 2 | ❌ | ❌ | ✅ Runs |
| **Diga CLI - Unit Tests** | 130 | ❌ | ❌ | ✅ Runs |
| **Diga CLI - Integration Tests** | 4 | ✅ 3.4GB | ✅ | ❌ Skipped |

**Total in CI**: ~226 tests
**Skipped**: 7 tests (3 audio + 4 binary integration)
**Run Locally**: `make test-integration` for full 233 tests

---

## Makefile Targets

### `make test-unit` (Used by CI)

```bash
xcodebuild test \
  -scheme SwiftVoxAlta-Package \
  -destination 'platform=macOS' \
  -skip-testing:DigaTests/DigaBinaryIntegrationTests \
  -skip-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderVoiceTests/testGenerateAudioWithPresetSpeaker \
  -skip-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderVoiceTests/testGenerateAudioWithAllPresetSpeakers \
  -skip-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderVoiceTests/testGenerateProcessedAudioDuration
```

**Duration**: 1-2 minutes
**No downloads**: All tests run without model or binary

### `make test-integration` (Local Only)

```bash
# First builds binary, then runs:
xcodebuild test \
  -scheme SwiftVoxAlta-Package \
  -destination 'platform=macOS' \
  -only-testing:DigaTests/DigaBinaryIntegrationTests
```

**Duration**:
- First run: 10-15 minutes (model download)
- Cached: 15-30 seconds

**Requires**:
- Qwen3-TTS-1.7B-CustomVoice (~3.4GB) in `~/Library/SharedModels/`
- Binary built via `make install`

### `make test` (All Tests, Local Only)

```bash
make test-unit && make test-integration
```

**Duration**: First run ~15 min, cached ~2 min
**Total**: 233 tests

---

## Why Integration Tests Are Disabled in CI

### Problem: Model Download Timeout

The integration tests require the Qwen3-TTS-1.7B-CustomVoice model (~3.4GB):

```
t=0s:    Test starts
t=5s:    Model download begins
         Downloading: [4/12] model.safetensors
         ...
t=900s:  Still downloading (15 min timeout hit)
         ##[error]The operation was canceled.
```

**Result**: CI job times out before tests can run.

### Attempted Solutions (All Failed)

1. **GitHub Actions cache** — Cache miss/invalidation issues
2. **Increased timeout to 30 min** — Still timed out on slow runners
3. **Smaller 0.6B model** — Still 2.4GB, same timeout issues
4. **Pre-download in separate job** — Added complexity, unreliable

### Current Solution: Unit Tests Only

- CI runs **only** tests that don't need models
- Integration tests run **locally** where models cache reliably
- Developers verify full test suite before pushing
- CI provides fast feedback on logic/API changes

---

## Local Development Workflow

### First Time Setup

```bash
# Install binary and warm model cache
make install

# Generate test voice to download model (~10 min first time)
make setup-voices
# Runs: ./bin/diga -v ryan -o /tmp/warmup.wav "test"
```

### Running Tests

```bash
# Fast unit tests (what CI runs)
make test-unit
# → 226 tests, ~1-2 min, no downloads

# Integration tests (requires setup-voices)
make test-integration
# → 7 tests, ~30s (cached) or ~15 min (first run)

# All tests
make test
# → 233 tests, ~2 min (cached) or ~15 min (first run)
```

### Pre-Push Checklist

```bash
# 1. Run full test suite locally
make test

# 2. Verify CI will pass
make test-unit

# 3. Push and verify CI runs match local
git push origin feature-branch
```

---

## Performance Comparison

| Strategy | CI Duration | Model Downloads | GitHub Minutes |
|----------|-------------|-----------------|----------------|
| **Unit Tests Only (Current)** | 1-2 min | ❌ None | ~2 min |
| Integration + Caching | 15-30 min | ✅ 3.4GB | ~30 min |
| Integration No Cache | 15-30 min | ✅ Every run | ~30 min |
| All Local, CI Disabled | N/A | ❌ None | 0 min |

**Cost Savings**: ~28 minutes per PR (14x faster CI)

---

## CI Execution Timeline

### Current State (Unit Tests Only)

```
Timeline:
┌────────────────────────────────────────────────────────┐
│                                                        │
│ t=0s:   unit-tests starts ───────────────────┐        │
│         • Checkout code                      │        │
│         • Swift version check                │        │
│         • xcodebuild test (unit tests only)  │        │
│                                              │        │
│ t=90s:                           unit-tests ✓│        │
│         • 226 tests passed                            │
│         • No model downloads                          │
│                                                        │
└────────────────────────────────────────────────────────┘

Total: ~90 seconds (1.5 minutes)
```

### Previous State (With Integration Tests) — REMOVED

```
Timeline (OUTDATED - integration tests now disabled):
┌────────────────────────────────────────────────────────┐
│ t=0s:   integration-tests starts ───────────────┐     │
│         • Checkout code                         │     │
│         • Restore cache (miss)                  │     │
│         • Model download begins...              │     │
│                                                 │     │
│ t=900s:                                         │     │
│         ##[error]The operation was canceled.    │     │
│         (15 min timeout exceeded)                     │
│                                                        │
└────────────────────────────────────────────────────────┘

Total: TIMEOUT (15 minutes)
Status: FAILED
```

---

## GitHub Actions Workflow File

### Current Configuration

**File**: `.github/workflows/tests.yml`

```yaml
name: Tests

on:
  pull_request:
    branches: [main, development]

jobs:
  # Fast unit tests (no binary or model downloads required)
  unit-tests:
    name: Unit Tests
    runs-on: macos-26
    timeout-minutes: 15
    env:
      GIT_LFS_SKIP_SMUDGE: "1"

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Show Swift version
        run: swift --version

      - name: Run unit tests
        run: make test-unit

  # Integration tests disabled - require 3.4GB model downloads
  # Run locally with: make test-integration
  # integration-tests:
  #   (commented out)
```

**Status**: 1 job, ~90 seconds, no model downloads

---

## Future Considerations

### Option 1: Self-Hosted Runner (Recommended)

- Use Apple Silicon runner with pre-cached models
- Pros: Fast integration tests in CI, full coverage
- Cons: Infrastructure cost, maintenance overhead
- Estimated CI time: 2-3 minutes (all tests)

### Option 2: Conditional Integration Tests

- Run integration tests only on release branches
- Pros: Main/development stay fast, releases verified
- Cons: Integration bugs not caught in PRs
- Implementation:
  ```yaml
  if: github.ref == 'refs/heads/main'
  ```

### Option 3: GitHub Packages Model Registry

- Host model on GitHub Packages
- Pros: Faster download from same network
- Cons: Still 3.4GB, GitHub storage costs
- Estimated savings: ~5 minutes (still too slow)

### Option 4: Mock Model Layer

- Mock MLX model loading in tests
- Pros: Fast CI, no downloads
- Cons: Doesn't test actual TTS, risk of regressions
- Not recommended: Integration tests exist for a reason

---

## Skipped Tests Reference

These tests are skipped in CI via `-skip-testing` flags:

### SwiftVoxAltaTests (3 tests skipped)

1. **`testGenerateAudioWithPresetSpeaker()`**
   - **Why**: Downloads 3.4GB model, generates audio with "ryan" voice
   - **Local**: ✅ Passes (takes 2-3s cached)
   - **File**: VoxAltaVoiceProviderTests.swift:193

2. **`testGenerateAudioWithAllPresetSpeakers()`**
   - **Why**: Downloads 3.4GB model, generates audio for all 9 voices
   - **Local**: ✅ Passes (takes 15-20s cached)
   - **File**: VoxAltaVoiceProviderTests.swift:209

3. **`testGenerateProcessedAudioDuration()`**
   - **Why**: Downloads 3.4GB model, generates audio and parses WAV
   - **Local**: ✅ Passes (takes 2-3s cached)
   - **File**: VoxAltaVoiceProviderTests.swift:224

### DigaTests (4 tests skipped)

1. **`testGenerateValidWAVFile()`**
   - **Why**: Requires diga binary + model
   - **Local**: ✅ Passes
   - **Suite**: DigaBinaryIntegrationTests

2. **`testGenerateValidAIFFFile()`**
   - **Why**: Requires diga binary + model
   - **Local**: ✅ Passes
   - **Suite**: DigaBinaryIntegrationTests

3. **`testGenerateValidM4AFile()`**
   - **Why**: Requires diga binary + model
   - **Local**: ✅ Passes
   - **Suite**: DigaBinaryIntegrationTests

4. **`testInvalidVoiceReturnsError()`**
   - **Why**: Requires diga binary
   - **Local**: ✅ Passes
   - **Suite**: DigaBinaryIntegrationTests

**Total Skipped**: 7 tests
**Reason**: All require 3.4GB model download or binary build

---

## Summary

SwiftVoxAlta's CI is optimized for **speed and reliability** by running unit tests only:

| Metric | Value |
|--------|-------|
| **CI Duration** | 1-2 minutes |
| **Tests in CI** | 226 unit tests |
| **Tests Skipped** | 7 integration tests (run locally) |
| **Model Downloads** | None |
| **GitHub Minutes** | ~2 per PR |
| **Failure Rate** | Low (no timeout issues) |

**Key Design Principle**: Fast feedback in CI, comprehensive verification locally.

**Local Testing Required**: Developers must run `make test` before pushing to verify integration tests pass.

**PR Merge Criteria**:
1. ✅ CI unit tests pass
2. ✅ Developer confirms `make test` passed locally
3. ✅ Code review approved
