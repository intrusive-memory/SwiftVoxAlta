# CustomVoice Migration Guide

**Date**: 2026-02-12

## Overview

SwiftVoxAlta has migrated from VoiceDesign/Base cloning to Qwen3-TTS CustomVoice with preset speakers. This guide documents the migration and new voice system.

---

## What Changed

### Before: VoiceDesign + Base Cloning

**Workflow**:
1. User creates voice with `--design "description"` or `--clone reference.wav`
2. First use: Generate reference audio (VoiceDesign: 10+ min, Base cloning: tensor errors)
3. Extract clone prompt from reference audio
4. Cache clone prompt to disk
5. Synthesize using clone prompt

**Problems**:
- VoiceDesign: 10+ minutes for 10 words (unusable)
- Base cloning: Fatal tensor shape errors in clone prompt extraction
- Complex caching and generation pipeline
- Unreliable due to upstream bugs

### After: CustomVoice Preset Speakers

**Workflow**:
1. User selects built-in preset voice (ryan, aiden, vivian, serena, anna, sohee)
2. Synthesize directly using CustomVoice model (~4-7 seconds)
3. No clone prompts, no reference audio, no caching needed

**Benefits**:
- ✅ Fast: 4-7 seconds per sentence (vs 10+ minutes)
- ✅ Reliable: No upstream bugs
- ✅ Simple: No clone prompt pipeline
- ✅ High quality: Professionally designed voices
- ✅ Multilingual: All voices speak 10 languages

---

## Built-in Voices

### English Speakers

| Voice | Speaker ID | Description |
|-------|------------|-------------|
| `ryan` | `ryan` | Dynamic male voice with strong rhythmic drive |
| `aiden` | `aiden` | Sunny American male voice with clear midrange |

### Multilingual Speakers

| Voice | Speaker ID | Native Language | Description |
|-------|------------|----------------|-------------|
| `vivian` | `vivian` | Chinese | Bright, slightly edgy young female voice |
| `serena` | `serena` | Chinese | Warm, gentle young female voice |
| `anna` | `ono_anna` | Japanese | Playful female voice with light timbre |
| `sohee` | `sohee` | Korean | Warm female voice with rich emotion |

**Note**: All voices can speak English, Chinese, Japanese, Korean, German, French, Russian, Portuguese, Spanish, and Italian. Quality is best in their native language.

---

## Model Details

**Model**: `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16`
**Size**: 3.4 GB
**Download**: Auto-downloaded on first use, cached at `~/Library/Caches/intrusive-memory/Models/Audio/`
**Sample Rate**: 24 kHz, 16-bit PCM, mono
**Output Formats**: WAV, AIFF, M4A

---

## Usage Examples

### List Available Voices

```bash
./bin/diga --voices
```

Output:
```
Built-in:
  ryan    Dynamic male voice with strong rhythmic drive
  aiden   Sunny American male voice with clear midrange
  vivian  Bright, slightly edgy young female voice
  serena  Warm, gentle young female voice
  anna    Playful Japanese female voice with light timbre
  sohee   Warm Korean female voice with rich emotion

Custom:
  (none — use --design or --clone to create)
```

### Generate Audio

```bash
# Using ryan voice (male)
./bin/diga -v ryan -o output.wav "Hello, this is a test."

# Using serena voice (female)
./bin/diga -v serena -o output.wav "Testing the serena voice."

# Using default voice (ryan if unspecified)
./bin/diga -o output.wav "Default voice test."
```

### Format Conversion

```bash
# AIFF format
./bin/diga -v aiden -o output.aiff "Testing AIFF format"

# M4A format
./bin/diga -v vivian -o output.m4a "Testing M4A format"
```

---

## Architecture Changes

### VoiceStore

**New Voice Type**: Added `.preset` to `VoiceType` enum

```swift
enum VoiceType: String, Codable, Sendable {
    case builtin
    case designed
    case cloned
    case preset  // CustomVoice preset speaker
}
```

**Storage**: Preset voices store the CustomVoice speaker name in `clonePromptPath` field (e.g., "ryan", "aiden", "ono_anna")

### BuiltinVoices

**Before** (macOS `say` voices):
```swift
("alex", "Male, American, warm baritone", "Alex"),
("samantha", "Female, American, clear soprano", "Samantha"),
```

**After** (CustomVoice speakers):
```swift
("ryan", "ryan", "Dynamic male voice with strong rhythmic drive"),
("aiden", "aiden", "Sunny American male voice with clear midrange"),
```

### DigaEngine

**New Method**: `synthesizeWithPresetSpeaker()`

```swift
nonisolated private func synthesizeWithPresetSpeaker(
    text: String,
    speakerName: String,
    voiceName: String,
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo
) async throws -> Data
```

**Routing Logic** in `synthesize()`:
```swift
if voice.type == .preset, let speakerName = voice.clonePromptPath {
    return try await synthesizeWithPresetSpeaker(
        text: text,
        speakerName: speakerName,
        voiceName: voice.name,
        modelManager: voxAltaModelManager,
        modelRepo: resolvedBaseModelRepo
    )
}
```

### VoxAltaModelManager

**New Enum Cases**:
```swift
case customVoice1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"
case customVoice0_6B = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
```

**Default Model**: Changed from `.base0_6B` to `.customVoice1_7B`

---

## Testing

### Integration Tests

**Updated**: `Tests/DigaTests/DigaBinaryIntegrationTests.swift`

**Changes**:
- Voice changed from `alex` to `ryan`
- Timeout increased from 30s to 60s (model download on first run)
- Documentation updated for CustomVoice model caching

**Test Results**:
```
✓ WAV generation:  7.1s  (RMS=0.12, Peak=0.61)
✓ AIFF generation: 4.8s  (RMS=0.09, Peak=0.51)
✓ M4A generation:  4.5s  (RMS=0.06, Peak=0.29)
✓ Error handling:  0.0s
```

### Makefile

**Updated**: `setup-voices` target

**Before**:
```makefile
setup-voices: install
	@echo "Generating built-in voices for local testing..."
	@./bin/diga -v alex -o /tmp/warmup.wav "test"
```

**After**:
```makefile
setup-voices: install
	@echo "Downloading CustomVoice model (~3.4GB, first run only)..."
	@./bin/diga -v ryan -o /tmp/warmup.wav "test"
```

---

## Migration Checklist

If you're upgrading from an older version:

- [ ] Pull latest changes from `main` or `development` branch
- [ ] Run `make install` to rebuild binary
- [ ] Run `make setup-voices` to download CustomVoice model (~3.4GB)
- [ ] Update any scripts using `alex`, `samantha`, `daniel`, `karen` voices to use new names:
  - `alex` → `ryan` (male)
  - `samantha` → `serena` (female)
  - `daniel` → `aiden` (male)
  - `karen` → `vivian` (female)
- [ ] Test voice generation: `./bin/diga -v ryan -o test.wav "hello"`
- [ ] Remove old cache if needed: `rm -rf ~/.diga/voices/*.cloneprompt`

---

## Future Work

### Planned Enhancements

1. **Custom Voice Design**: Re-enable `--design` once VoiceDesign performance improves
2. **Voice Cloning**: Re-enable `--clone` once Base clone prompt extraction is fixed
3. **Additional Speakers**: Add remaining CustomVoice speakers (uncle_fu, dylan, eric)
4. **Emotion Control**: Support CustomVoice emotion parameters when available

### Upstream Contributions

- File issue for VoiceDesign performance (10+ min generation time)
- File issue for Base clone prompt tensor shape mismatch
- Contribute CustomVoice API improvements back to mlx-audio-swift

---

## References

- **Qwen3-TTS Documentation**: https://github.com/QwenLM/Qwen3-TTS
- **mlx-audio-swift**: https://github.com/Blaizzy/mlx-audio-swift
- **CustomVoice Model**: https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16

---

**End of Migration Guide**
