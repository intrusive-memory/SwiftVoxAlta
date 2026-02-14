# CustomVoice Implementation - Execution Plan

**Date**: 2026-02-12
**Status**: PLANNING
**Goal**: Implement Qwen3-TTS CustomVoice support to bypass VoiceDesign/Base model bugs

---

## Executive Summary

**Problem**: Both Qwen3-TTS approaches are blocked:
- VoiceDesign: Takes 10+ minutes for 10-word sample (unusable)
- Base cloning: Fatal tensor shape error during clone prompt extraction

**Solution**: Use CustomVoice models with 9 preset speakers
- No voice design needed (uses built-in speakers)
- No clone prompt extraction needed (speakers embedded in model)
- Fast generation (text → audio directly)
- High quality (professionally designed voices)

**Impact**: Unblocks all integration tests and enables production use

---

## CustomVoice Model Details

### Preset Speakers (9 total)

| Speaker | Language | Gender | Description |
|---------|----------|--------|-------------|
| **ryan** | English | Male | Dynamic voice with strong rhythmic drive |
| **aiden** | English | Male | Sunny American voice with clear midrange |
| **vivian** | Chinese | Female | Bright, slightly edgy young voice |
| **serena** | Chinese | Female | Warm, gentle young voice |
| **uncle_fu** | Chinese | Male | Seasoned voice with low, mellow timbre |
| **dylan** | Chinese (Beijing) | Male | Youthful Beijing voice with clear timbre |
| **eric** | Chinese (Sichuan) | Male | Lively Chengdu voice with husky brightness |
| **ono_anna** | Japanese | Female | Playful voice with light, nimble timbre |
| **sohee** | Korean | Female | Warm voice with rich emotion |

**Note**: All speakers can speak all 10 supported languages (Chinese, English, Japanese, Korean, German, French, Russian, Portuguese, Spanish, Italian), though quality is best in their native language.

### Model Variants

- `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16` (3.4GB)
- `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16` (1.2GB)

---

## Architecture Changes

### 1. Add CustomVoice Model Support

**File**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

**Changes**:
```swift
public enum Qwen3TTSModelRepo: String, CaseIterable, Sendable {
    // ... existing cases ...

    /// CustomVoice model (1.7B parameters, bf16 precision).
    /// Includes 9 preset speakers (no clone prompt needed).
    case customVoice1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"

    /// CustomVoice model (0.6B parameters, bf16 precision).
    /// Lighter-weight with 9 preset speakers.
    case customVoice0_6B = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
}
```

**Update**:
- `displayName` switch statement
- `knownSizes` dictionary with model sizes

---

### 2. Add Preset Voice Type

**File**: `Sources/diga/VoiceStore.swift`

**Changes**:
```swift
enum VoiceType: String, Codable, Sendable {
    case builtin
    case designed
    case cloned
    case preset  // CustomVoice preset speaker (no clone prompt needed)
}
```

---

### 3. Update Built-in Voices

**File**: `Sources/diga/BuiltinVoices.swift`

**Changes**:
```swift
private static let definitions: [(name: String, speaker: String, description: String)] = [
    // English speakers
    ("ryan", "ryan", "Dynamic male voice with strong rhythmic drive"),
    ("aiden", "aiden", "Sunny American male voice with clear midrange"),

    // Multilingual speakers (can speak English too)
    ("vivian", "vivian", "Bright, slightly edgy young female voice"),
    ("serena", "serena", "Warm, gentle young female voice"),
    ("anna", "ono_anna", "Playful Japanese female voice with light timbre"),
    ("sohee", "sohee", "Warm Korean female voice with rich emotion"),
]

static func all() -> [StoredVoice] {
    definitions.map { entry in
        StoredVoice(
            name: entry.name,
            type: .preset,
            designDescription: entry.description,
            clonePromptPath: entry.speaker,  // Store CustomVoice speaker name
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }
}
```

---

### 4. Update Default Model

**File**: `Sources/diga/DigaEngine.swift`

**Changes**:
```swift
private var resolvedBaseModelRepo: Qwen3TTSModelRepo {
    guard let override = modelOverride else { return .customVoice1_7B }
    // ... existing logic ...
    return .customVoice1_7B  // Default to CustomVoice
}
```

---

### 5. Add Preset Speaker Synthesis

**File**: `Sources/diga/DigaEngine.swift`

**New Method**:
```swift
func synthesize(text: String, voiceName: String? = nil) async throws -> Data {
    let voice = try resolveVoice(name: voiceName)

    // For preset voices, use speaker name directly
    if voice.type == .preset, let speakerName = voice.clonePromptPath {
        return try await synthesizeWithPresetSpeaker(
            text: text,
            speakerName: speakerName,
            voiceName: voice.name
        )
    }

    // Existing clone prompt flow for other voice types
    // ...
}

private func synthesizeWithPresetSpeaker(
    text: String,
    speakerName: String,
    voiceName: String
) async throws -> Data {
    // 1. Load CustomVoice model
    let model = try await voxAltaModelManager.loadModel(resolvedBaseModelRepo)
    guard let qwenModel = model as? Qwen3TTSModel else {
        throw DigaEngineError.synthesisFailed("Not a Qwen3TTSModel")
    }

    // 2. Chunk text
    let chunks = TextChunker.chunk(text)

    // 3. Generate each chunk with CustomVoice speaker
    var wavSegments: [Data] = []
    for chunk in chunks {
        let audioArray = try await qwenModel.generateCustomVoice(
            text: chunk,
            speaker: speakerName,
            language: "en"
        )
        let wavData = try AudioConversion.mlxArrayToWAVData(
            audioArray,
            sampleRate: qwenModel.sampleRate
        )
        wavSegments.append(wavData)
    }

    // 4. Concatenate WAV segments
    return try WAVConcatenator.concatenate(wavSegments)
}
```

---

### 6. Update Voice Listing

**File**: `Sources/diga/DigaCommand.swift`

**Changes**:
```swift
switch voice.type {
case .designed:
    description = voice.designDescription ?? "(designed)"
case .cloned:
    description = "cloned from \(voice.clonePromptPath ?? "reference audio")"
case .builtin:
    description = voice.designDescription ?? ""
case .preset:
    description = "preset speaker: \(voice.clonePromptPath ?? "unknown")"
}
```

---

## Implementation Sprints

### Sprint 1: Model Infrastructure (30 min)
**Files**: `VoxAltaModelManager.swift`

**Tasks**:
1. Add `customVoice1_7B` and `customVoice0_6B` enum cases
2. Update `displayName` switch statement
3. Add model sizes to `knownSizes` dictionary
4. **Test**: Verify enum compiles and displays correctly

---

### Sprint 2: Voice Type Support (15 min)
**Files**: `VoiceStore.swift`, `DigaCommand.swift`

**Tasks**:
1. Add `.preset` case to `VoiceType` enum
2. Update `DigaCommand` switch statement for voice listing
3. **Test**: Verify `diga --voices` compiles

---

### Sprint 3: Built-in Voices (15 min)
**Files**: `BuiltinVoices.swift`

**Tasks**:
1. Update voice definitions with CustomVoice speaker names
2. Change type from `.cloned` to `.preset`
3. Store speaker name in `clonePromptPath`
4. **Test**: Verify voice list shows preset speakers

---

### Sprint 4: Engine Integration (45 min)
**Files**: `DigaEngine.swift`

**Tasks**:
1. Update `resolvedBaseModelRepo` default to `.customVoice1_7B`
2. Add `synthesizeWithPresetSpeaker()` method
3. Update `synthesize()` to route preset voices to new method
4. **Test**: Verify compilation, check for type errors

**Critical**: Research correct API for `Qwen3TTSModel.generate()` with CustomVoice:
- Check mlx-audio-swift examples for CustomVoice usage
- Verify parameter types (`GenerateParameters` vs `AudioGenerateParameters`)
- Confirm speaker name parameter format

---

### Sprint 5: Integration Testing (30 min)

**Tasks**:
1. Build diga binary: `make install`
2. Test voice listing: `diga --voices`
3. Test synthesis: `diga -v ryan -o /tmp/test.wav "Hello world"`
4. Verify model auto-download works
5. Verify audio quality with AVAudioFile
6. **Expected**: ~30s first run (model download), ~2-5s subsequent runs

---

### Sprint 6: Documentation (15 min)

**Tasks**:
1. Update `README.md` with new voice names
2. Update `INTEGRATION_TESTS_STATUS.md` with solution
3. Create `docs/CUSTOMVOICE_MIGRATION.md` guide
4. Document preset speaker capabilities

---

## Critical Research Items

Before Sprint 4, investigate:

1. **CustomVoice API in mlx-audio-swift**
   - Check `Examples/VoicesApp` for CustomVoice usage
   - Find correct `generate()` method signature
   - Verify parameter types

2. **Speaker Name Format**
   - Confirm speaker names match config.json exactly
   - Check if case-sensitive

3. **Generation Parameters**
   - Determine correct struct type
   - Check if module exports are needed

**Files to Check**:
- `mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`
- `mlx-audio-swift/Examples/VoicesApp/VoicesApp/ViewModels/TTSViewModel.swift`
- `mlx-audio-swift/Sources/MLXAudioCore/Generation/GenerationTypes.swift`

---

## Success Criteria

- [ ] diga compiles without errors
- [ ] `diga --voices` lists 6 preset voices
- [ ] `diga -v ryan "hello"` generates audio in <5s (after model cached)
- [ ] First run auto-downloads CustomVoice model
- [ ] Integration tests pass (3/4 - WAV, AIFF, M4A generation)
- [ ] Audio validation passes (24kHz, mono, RMS > 0.02, Peak > 0.1)

---

## Rollback Plan

If CustomVoice fails:
1. `git revert` to commit `a26746b`
2. Fallback to Option A: Use macOS `say` directly
3. File upstream issues with mlx-audio-swift
4. Consider alternative TTS engines

---

## Timeline Estimate

- Sprint 1-3: 1 hour (infrastructure)
- Sprint 4 (critical): 1-2 hours (includes research)
- Sprint 5-6: 45 minutes (testing + docs)

**Total**: 2.5-3.5 hours

---

## Next Steps

1. Review this plan with user
2. Research CustomVoice API (critical research items)
3. Execute sprints in order
4. Test incrementally
5. Document findings

---

**Status**: Ready for review and execution approval
