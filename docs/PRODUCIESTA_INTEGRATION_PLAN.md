# VoxAlta → Produciesta Integration Execution Plan

**Date**: 2026-02-12
**Status**: PLANNING
**Goal**: Integrate VoxAlta CustomVoice preset speakers as a voice provider in Produciesta

---

## Executive Summary

**Objective**: Update VoxAltaVoiceProvider to support CustomVoice preset speakers and integrate it with Produciesta for character voice assignment.

**Approach**: Dual-mode provider supporting both:
1. **CustomVoice preset speakers** (9 voices, fast, reliable) - PRIMARY
2. **Clone prompts** (custom voices, for future when bugs are fixed) - FALLBACK

**Impact**: Enables production-ready voice generation in Produciesta with 9 high-quality preset voices.

---

## Current State Analysis

### VoxAlta (SwiftVoxAlta)

**Implemented**:
- ✅ CustomVoice model support (9 preset speakers)
- ✅ diga CLI with preset speaker synthesis
- ✅ All integration tests passing
- ✅ VoxAltaVoiceProvider protocol conformance
- ✅ VoxAltaModelManager actor
- ✅ VoiceLockManager for clone prompts

**Needs Update**:
- ❌ VoxAltaVoiceProvider uses clone prompts only (old approach)
- ❌ fetchVoices() returns empty array (no preset speakers listed)
- ❌ generateAudio() requires pre-loaded clone prompts

### Produciesta (../Produciesta)

**Current Voice Providers**:
- Apple TTS (AIFF format)
- ElevenLabs (MP3 format, API key required)
- Qwen (WAV format, currently broken)

**Integration Points**:
- VoiceProviderRegistry for provider registration
- Voice selection UI (dropdown per character)
- Audio generation during podcast rendering
- SwiftData storage for processed audio

---

## Architecture Changes

### 1. VoxAltaVoiceProvider Updates

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

#### Add Preset Speaker Support

**New Property**:
```swift
/// The 9 CustomVoice preset speakers available without clone prompts
private static let presetSpeakers: [(id: String, name: String, description: String, gender: String)] = [
    ("ryan", "Ryan", "Dynamic male voice with strong rhythmic drive", "male"),
    ("aiden", "Aiden", "Sunny American male voice with clear midrange", "male"),
    ("vivian", "Vivian", "Bright, slightly edgy young Chinese female voice", "female"),
    ("serena", "Serena", "Warm, gentle young Chinese female voice", "female"),
    ("uncle_fu", "Uncle Fu", "Seasoned Chinese male voice with low, mellow timbre", "male"),
    ("dylan", "Dylan", "Youthful Beijing male voice with clear timbre", "male"),
    ("eric", "Eric", "Lively Chengdu male voice with husky brightness", "male"),
    ("anna", "Anna", "Playful Japanese female voice with light timbre", "female"),
    ("sohee", "Sohee", "Warm Korean female voice with rich emotion", "female"),
]
```

#### Update fetchVoices()

**Before** (returns empty):
```swift
public func fetchVoices(languageCode: String) async throws -> [Voice] {
    let cached = await voiceCache.allVoices()
    return cached.map { entry in
        Voice(id: entry.id, name: entry.id, ...)
    }
}
```

**After** (returns presets + cached):
```swift
public func fetchVoices(languageCode: String) async throws -> [Voice] {
    // Return preset speakers
    var voices = Self.presetSpeakers.map { speaker in
        Voice(
            id: speaker.id,
            name: speaker.name,
            description: speaker.description,
            providerId: providerId,
            language: languageCode,
            gender: speaker.gender
        )
    }

    // Add any custom voices loaded via loadVoice() (for future use)
    let cached = await voiceCache.allVoices()
    voices.append(contentsOf: cached.map { entry in
        Voice(
            id: entry.id,
            name: "Custom: \(entry.id)",
            description: "Custom cloned voice",
            providerId: providerId,
            language: languageCode,
            gender: entry.voice.gender
        )
    })

    return voices
}
```

#### Update generateAudio() - Dual Mode

**Add helper**:
```swift
private func isPresetSpeaker(_ voiceId: String) -> Bool {
    Self.presetSpeakers.contains { $0.id == voiceId }
}
```

**Update main method**:
```swift
public func generateAudio(text: String, voiceId: String, languageCode: String) async throws -> Data {
    // Route 1: CustomVoice preset speaker (fast path)
    if isPresetSpeaker(voiceId) {
        return try await generateWithPresetSpeaker(
            text: text,
            speakerName: voiceId,
            language: languageCode
        )
    }

    // Route 2: Clone prompt (custom voice, for future use)
    guard let cached = await voiceCache.get(id: voiceId) else {
        throw VoxAltaError.voiceNotLoaded(voiceId)
    }

    let voiceLock = VoiceLock(
        characterName: voiceId,
        clonePromptData: cached.clonePromptData,
        designInstruction: ""
    )

    return try await VoiceLockManager.generateAudio(
        text: text,
        voiceLock: voiceLock,
        language: languageCode,
        modelManager: modelManager
    )
}
```

#### Add New Method: generateWithPresetSpeaker()

```swift
/// Generate audio using a CustomVoice preset speaker.
///
/// This bypasses the clone prompt workflow entirely and directly uses
/// the CustomVoice model with the specified speaker name.
///
/// - Parameters:
///   - text: The text to synthesize.
///   - speakerName: The CustomVoice speaker name (e.g., "ryan", "aiden").
///   - language: The language code for generation.
/// - Returns: WAV format audio data.
private func generateWithPresetSpeaker(
    text: String,
    speakerName: String,
    language: String
) async throws -> Data {
    // Load CustomVoice model
    let model = try await modelManager.loadModel(.customVoice1_7B)

    guard let qwenModel = model as? Qwen3TTSModel else {
        throw VoxAltaError.modelNotAvailable(
            "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
        )
    }

    // Generate audio with CustomVoice speaker
    let audioArray: MLXArray
    do {
        audioArray = try await qwenModel.generate(
            text: text,
            voice: speakerName,
            refAudio: nil,
            refText: nil,
            language: language,
            generationParameters: GenerateParameters()
        )
    } catch {
        throw VoxAltaError.generationFailed(
            "Failed to generate audio with speaker '\(speakerName)': \(error.localizedDescription)"
        )
    }

    // Convert to WAV
    return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
}
```

#### Update isVoiceAvailable()

```swift
public func isVoiceAvailable(voiceId: String) async -> Bool {
    // Preset speakers are always available
    if isPresetSpeaker(voiceId) {
        return true
    }

    // Check cache for custom voices
    let cached = await voiceCache.get(id: voiceId)
    return cached != nil
}
```

#### Add Imports

```swift
import MLX
import MLXAudioTTS
import MLXLMCommon
```

Use `@preconcurrency` if needed for Sendable warnings.

---

### 2. Produciesta Integration

**File**: `../Produciesta/Sources/.../VoiceProviderRegistry.swift` (or equivalent)

#### Register VoxAltaVoiceProvider

```swift
import SwiftVoxAlta

// In initialization or setup
let voxAltaProvider = VoxAltaVoiceProvider()
registry.register(provider: voxAltaProvider)
```

#### Update UI

**Voice Selection Dropdown**:
- Shows 9 preset speakers for VoxAlta provider
- Display format: "Ryan - Dynamic male voice with strong rhythmic drive"
- Group by provider: "VoxAlta (On-Device)"

**Provider Settings**:
- No API key required
- Show model download status on first use
- Display "Model: CustomVoice 1.7B (3.4GB)"

---

## Implementation Sprints

### Sprint 1: VoxAltaVoiceProvider Updates (60 min)

**Files**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

**Tasks**:
1. Add `presetSpeakers` static array (9 voices)
2. Add `isPresetSpeaker()` helper method
3. Update `fetchVoices()` to return preset speakers
4. Add `generateWithPresetSpeaker()` private method
5. Update `generateAudio()` with dual-mode routing
6. Update `isVoiceAvailable()` to include presets
7. Add required imports (`MLX`, `MLXAudioTTS`, `MLXLMCommon`)
8. Use `@preconcurrency` imports if needed

**Test**:
```swift
let provider = VoxAltaVoiceProvider()
let voices = try await provider.fetchVoices(languageCode: "en")
// Expected: 9 voices returned

let audio = try await provider.generateAudio(
    text: "Hello from VoxAlta",
    voiceId: "ryan",
    languageCode: "en"
)
// Expected: WAV data generated successfully
```

---

### Sprint 2: Unit Tests (30 min)

**File**: `Tests/SwiftVoxAltaTests/VoxAltaVoiceProviderTests.swift`

**Tests**:
1. `testFetchVoicesReturnsPresetSpeakers()` - Verify 9 voices
2. `testGenerateAudioWithPresetSpeaker()` - Generate with "ryan"
3. `testGenerateAudioWithAllPresetSpeakers()` - Loop through all 9
4. `testIsVoiceAvailableForPresets()` - Check preset availability
5. `testGenerateProcessedAudioDuration()` - Verify duration calculation
6. `testDualModeRouting()` - Verify preset vs clone prompt routing

**Expected Results**:
- All tests pass
- Audio generation takes 4-7 seconds per sentence
- WAV format validated (24kHz, mono, 16-bit PCM)

---

### Sprint 3: Produciesta Integration (45 min)

**Files**:
- `../Produciesta/.../VoiceProviderRegistry.swift`
- `../Produciesta/.../VoiceSelectionView.swift` (or equivalent)

**Tasks**:
1. Import SwiftVoxAlta package dependency
2. Register VoxAltaVoiceProvider in registry initialization
3. Update voice selection UI to display preset speakers
4. Test voice dropdown shows 9 VoxAlta voices
5. Verify provider displays as "VoxAlta (On-Device)"

**Verification**:
- Launch Produciesta
- Navigate to podcast settings
- Select a character
- Voice dropdown shows VoxAlta voices
- Select "Ryan" voice
- Generate test audio

---

### Sprint 4: End-to-End Testing (30 min)

**Scenario**: Generate podcast episode with VoxAlta voices

**Steps**:
1. Open podcast project in Produciesta
2. Assign VoxAlta voices to characters:
   - Character A → ryan
   - Character B → serena
   - Character C → aiden
3. Trigger audio generation for episode
4. Verify:
   - Audio generates successfully
   - Each character has distinct voice
   - Audio plays correctly in Produciesta player
   - SwiftData stores processed audio
   - No errors in console

**Expected Performance**:
- Generation: ~4-7 seconds per dialogue line
- First run: +30s for model download (one-time)
- Quality: RMS > 0.02, Peak > 0.1
- Format: WAV, 24kHz, mono

---

### Sprint 5: Documentation (15 min)

**Files**:
- `README.md` - Add Produciesta integration example
- `AGENTS.md` - Update VoiceProvider documentation
- `docs/PRODUCIESTA_INTEGRATION.md` - Create integration guide

**Content**:
- How to register VoxAltaVoiceProvider
- Voice selection workflow
- Performance characteristics
- Troubleshooting guide
- Example code snippets

---

## Success Criteria

- [ ] VoxAltaVoiceProvider returns 9 preset speakers in fetchVoices()
- [ ] generateAudio() works with all 9 preset speakers
- [ ] Dual-mode routing (preset vs clone prompt) implemented
- [ ] All VoxAltaVoiceProvider unit tests passing
- [ ] Produciesta successfully registers VoxAltaVoiceProvider
- [ ] Voice dropdown shows all 9 VoxAlta voices
- [ ] End-to-end audio generation works in Produciesta
- [ ] Audio quality validated (24kHz, mono, RMS > 0.02)
- [ ] Documentation updated

---

## Testing Strategy

### Unit Tests (SwiftVoxAlta)

```swift
@Test("Fetch voices returns all preset speakers")
func testFetchVoicesReturnsPresetSpeakers() async throws {
    let provider = VoxAltaVoiceProvider()
    let voices = try await provider.fetchVoices(languageCode: "en")

    #expect(voices.count == 9, "Should return 9 preset speakers")
    #expect(voices.map(\.id).contains("ryan"))
    #expect(voices.map(\.id).contains("aiden"))
    // ... check all 9
}

@Test("Generate audio with preset speaker")
func testGenerateAudioWithPresetSpeaker() async throws {
    let provider = VoxAltaVoiceProvider()
    let audio = try await provider.generateAudio(
        text: "Hello world",
        voiceId: "ryan",
        languageCode: "en"
    )

    #expect(audio.count > 44, "WAV should be larger than header")

    // Validate WAV format
    let riff = String(data: audio[0..<4], encoding: .ascii)
    #expect(riff == "RIFF")
}
```

### Integration Tests (Produciesta)

1. **Provider Registration**: Verify VoxAltaVoiceProvider appears in registry
2. **Voice Fetching**: Verify 9 voices returned
3. **Audio Generation**: Generate sample for each voice
4. **UI Integration**: Verify dropdown shows voices correctly
5. **End-to-End**: Full podcast episode with multiple VoxAlta voices

---

## Rollback Plan

If integration fails:

1. **Revert VoxAltaVoiceProvider changes**: `git revert <commit>`
2. **Fallback to existing providers**: Use Apple or ElevenLabs in Produciesta
3. **File issues**: Document blockers for future resolution
4. **Alternative**: Use diga CLI directly from Produciesta (shell exec)

---

## Timeline Estimate

| Sprint | Duration | Dependencies |
|--------|----------|--------------|
| Sprint 1: VoiceProvider Updates | 60 min | None |
| Sprint 2: Unit Tests | 30 min | Sprint 1 |
| Sprint 3: Produciesta Integration | 45 min | Sprint 1 |
| Sprint 4: E2E Testing | 30 min | Sprint 3 |
| Sprint 5: Documentation | 15 min | Sprint 4 |

**Total**: 3 hours (including testing and documentation)

---

## Dependencies

### SwiftVoxAlta
- ✅ CustomVoice model support (implemented)
- ✅ VoxAltaModelManager (implemented)
- ✅ AudioConversion helpers (implemented)
- ❌ VoxAltaVoiceProvider preset support (Sprint 1)

### Produciesta
- ✅ VoiceProvider protocol from SwiftHablare
- ✅ VoiceProviderRegistry
- ✅ Voice selection UI
- ✅ SwiftData audio storage
- ❌ SwiftVoxAlta package dependency (Sprint 3)

---

## Risk Mitigation

### Risk 1: Sendable Conformance Issues

**Mitigation**: Use `@preconcurrency import` and `nonisolated` methods as done in DigaEngine.

### Risk 2: Model Download on First Use

**Mitigation**:
- Show loading indicator in Produciesta UI
- Cache model after first download
- Provide manual download option: "Download VoxAlta model now"

### Risk 3: Performance in Produciesta

**Mitigation**:
- Generate audio in background task
- Show progress indicator
- Cache generated audio in SwiftData
- Use Task groups for parallel generation

---

## Next Steps

1. Review this plan with user
2. Execute Sprint 1 (VoxAltaVoiceProvider updates)
3. Execute Sprint 2 (Unit tests)
4. Switch to Produciesta repo for Sprint 3-4
5. Document findings in Sprint 5

---

**Status**: Ready for execution approval

**Estimated Completion**: 3 hours
