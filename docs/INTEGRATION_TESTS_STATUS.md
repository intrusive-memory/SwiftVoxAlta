# Integration Tests Status

**Last Updated**: 2026-02-12

## Overview

✅ **ALL TESTS PASSING** - Integration tests now use Qwen3-TTS CustomVoice model with preset speakers, bypassing all previous issues.

## Test Infrastructure

- **Location**: `Tests/DigaTests/DigaBinaryIntegrationTests.swift`
- **Status**: ✅ Complete and Passing
- **Test Count**: 4 tests (all passing)
  - WAV generation with audio validation
  - AIFF format conversion
  - M4A format conversion
  - Binary error handling

## Test Results (Latest Run)

```
✓ WAV generation:  7.1s  (RMS=0.12, Peak=0.61)
✓ AIFF generation: 4.8s  (RMS=0.09, Peak=0.51)
✓ M4A generation:  4.5s  (RMS=0.06, Peak=0.29)
✓ Error handling:  0.0s
Total:             16.4s
```

**Audio Quality**: All tests pass validation thresholds (RMS > 0.02, Peak > 0.1)

---

## Solution: CustomVoice Preset Speakers ✅

**Implementation**: Switched from VoiceDesign/Base cloning to CustomVoice model with 9 preset speakers.

**Built-in Voices**:
- `ryan` - Dynamic male voice with strong rhythmic drive
- `aiden` - Sunny American male voice with clear midrange
- `vivian` - Bright, slightly edgy young female voice
- `serena` - Warm, gentle young female voice
- `anna` - Playful Japanese female voice (ono_anna)
- `sohee` - Warm Korean female voice with rich emotion

**Benefits**:
- ✅ Fast generation (~4-7 seconds per sentence)
- ✅ No clone prompt extraction needed
- ✅ High quality professionally designed voices
- ✅ Multilingual support (all speakers can speak 10 languages)
- ✅ Reliable and stable

**Model**: `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16` (3.4GB)

---

## Previous Issues (All Resolved)

### Issue #1: SwiftAcervo Migration Symlink Bug ✅ FIXED

**Status**: FIXED (commit 7a607b8) - No longer relevant with CustomVoice

**Previous Issue**: Migration failed when trying to move symlinks
**Current State**: Models correctly stored in `~/Library/SharedModels/`

---

### Issue #2: Duplicate Models in Legacy Paths ✅ CLEANED

**Status**: CLEANED

**Previous Issue**: Models duplicated in legacy and Acervo paths
**Current State**: All models in `~/Library/SharedModels/` via SwiftAcervo

---

### Issue #3: VoiceDesign Performance ✅ BYPASSED

**Status**: BYPASSED - Using CustomVoice instead

**Previous Issue**: 10+ minutes for 10 words
**Current Solution**: 4-7 seconds per sentence with CustomVoice

---

### Issue #4: Base Clone Prompt Extraction ✅ BYPASSED

**Status**: BYPASSED - CustomVoice doesn't need clone prompts

**Previous Issue**: Fatal tensor shape error during clone prompt extraction
**Current Solution**: Preset speakers require no clone prompt extraction

---

## CI/CD Integration

**Cache Strategy**: Cache CustomVoice model (~3.4GB) in `cache-voices` job
**Test Job**: Integration tests depend on cached model
**Performance**:
- Cold cache (first run): ~105 seconds (model download + tests)
- Warm cache: ~25 seconds (tests only)

**GitHub Actions Configuration**:
- Job 1: `cache-voices` - Downloads/caches CustomVoice model in parallel with unit tests
- Job 2: `unit-tests` - Runs library tests in parallel
- Job 3: `integration-tests` - Depends on both, runs binary tests

See `docs/CI_DEPENDENCY_CHAIN.md` for detailed CI architecture.

---

## Running Tests Locally

### First Time Setup

```bash
# 1. Install diga binary
make install

# 2. Download CustomVoice model (~3.4GB, one-time)
make setup-voices

# Expected output:
# Downloading CustomVoice model (~3.4GB, first run only)...
# ✓ CustomVoice model cached at ~/Library/Caches/intrusive-memory/Models/
```

### Run Tests

```bash
# Run all tests (unit + integration)
make test

# Run just integration tests
make test-integration

# Run just unit tests (no binary required)
make test-unit
```

---

## Test Coverage

| Test | Validates |
|------|-----------|
| **WAV Generation** | File creation, RIFF/WAVE headers, 24kHz mono, non-silence |
| **AIFF Generation** | File creation, FORM/AIFF headers, 24kHz mono, non-silence |
| **M4A Generation** | File creation, ftyp container, 24kHz mono, non-silence |
| **Error Handling** | Binary not found gracefully handled |

**Audio Validation**:
- ✅ File exists and size > minimum (44 bytes WAV, 54 bytes AIFF, 100 bytes M4A)
- ✅ Magic bytes/headers match format
- ✅ AVAudioFile validates 24kHz, mono, correct format
- ✅ RMS > 0.02 and Peak > 0.1 (empirically validated thresholds)

---

## Migration from Previous Version

If you're upgrading from a version that used `alex`, `samantha`, `daniel`, or `karen` voices:

1. **Update voice references**:
   - `alex` → `ryan` (male)
   - `samantha` → `serena` (female)
   - `daniel` → `aiden` (male)
   - `karen` → `vivian` (female)

2. **Remove old cache** (optional):
   ```bash
   rm -rf ~/.diga/voices/*.cloneprompt
   ```

3. **Re-run setup**:
   ```bash
   make install
   make setup-voices
   ```

See `docs/CUSTOMVOICE_MIGRATION.md` for detailed migration guide.

---

**End of Status Report**
