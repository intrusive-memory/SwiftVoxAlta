# VoxAlta → Produciesta Integration Execution Plan (V4 - Atomic)

**Date**: 2026-02-13
**Status**: READY FOR EXECUTION
**Goal**: Integrate VoxAlta CustomVoice preset speakers as a voice provider in Produciesta

**Version**: V4 - Atomic sprints with machine-verifiable criteria
**Improvements from V3**:
- Split 9 sprints → 15 atomic sprints
- Discovery separated from implementation
- All exit criteria machine-verifiable with exact commands
- Bounded debugging sprints (max turns enforced)
- Smaller rollback units (1-2 tasks per sprint)

---

## Executive Summary

**Objective**: Update VoxAltaVoiceProvider to support CustomVoice preset speakers and integrate it with Produciesta for character voice assignment.

**Approach**: Dual-mode provider supporting both:
1. **CustomVoice preset speakers** (9 voices, fast, reliable) - PRIMARY
2. **Clone prompts** (ICL custom voices) - FALLBACK (for future use)

**Impact**: Enables production-ready voice generation in Produciesta with 9 high-quality preset voices.

**Sprint Count**: 15 sprints (~165 turns, ~3.5 hours)
**Parallelization**: 2 phases (28 turns of parallel work)

---

## Model Selection Strategy

| Model | Use For | Sprints | Total Turns | Rationale |
|-------|---------|---------|-------------|-----------|
| 🔴 **Opus 4.6** | Unfamiliar codebase discovery | 3a2.1, 4b | 30 (18%) | Deep reasoning prevents costly retries |
| 🟡 **Sonnet 4.5** | Standard development, tests | All others | 120 (73%) | Excellent for well-defined tasks |
| 🟢 **Haiku 4.5** | Documentation | 5 | 15 (9%) | Fast and cheap for templated content |

**ROI**: Spending ~$1 extra on Opus (2 sprints) prevents 50-100 turn retries on critical discovery points.

---

## Current State Analysis

### VoxAlta (SwiftVoxAlta)

**Implemented**:
- ✅ CustomVoice model support (9 preset speakers)
- ✅ diga CLI with preset speaker synthesis
- ✅ All integration tests passing (359 tests)
- ✅ VoxAltaVoiceProvider protocol conformance
- ✅ VoxAltaModelManager actor
- ✅ VoiceLockManager for clone prompts
- ✅ ICL support via mlx-audio-swift fork (f937fb6)

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

## Implementation Sprints

### Phase 1: VoxAlta Provider Implementation (Sprints 1a.1 - 2b)

---

### Sprint 1a.1: Add Preset Speaker Data
**Model**: 🟡 Sonnet 4.5
**Duration**: 5 turns (10% utilization)
**Time**: 7 min

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

**Scope**: Add preset speakers array ONLY (single atomic change)

**Tasks**:

1. Add `presetSpeakers` static array with 9 voices:
   ```swift
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

**Exit Criteria** (machine-verifiable):

```bash
# 1. Array exists in file
grep -q "private static let presetSpeakers" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ Array exists: $?"

# 2. Array has exactly 9 entries
COUNT=$(grep -o '("ryan"\|"aiden"\|"vivian"\|"serena"\|"uncle_fu"\|"dylan"\|"eric"\|"anna"\|"sohee")' Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift | wc -l | tr -d ' ')
test "$COUNT" -eq 9
echo "✓ Has 9 entries: $?"

# 3. File compiles
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Builds successfully: $?"
```

**Success**: All 3 commands return exit code 0

**Dependencies**: None (foundation sprint)

**Rollback**: Delete array if fails

---

### Sprint 1a.2: Voice Listing Methods
**Model**: 🟡 Sonnet 4.5
**Duration**: 10 turns (20% utilization)
**Time**: 13 min

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

**Scope**: Add methods for listing and checking voices (no generation yet)

**Tasks**:

1. Add `isPresetSpeaker()` helper:
   ```swift
   private func isPresetSpeaker(_ voiceId: String) -> Bool {
       Self.presetSpeakers.contains { $0.id == voiceId }
   }
   ```

2. Update `fetchVoices()` to return preset speakers:
   ```swift
   public func fetchVoices(languageCode: String) async throws -> [Voice] {
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

       // Add cached custom voices (for future use)
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

3. Update `isVoiceAvailable()`:
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

**Exit Criteria** (machine-verifiable):

```bash
# 1. isPresetSpeaker() exists
grep -q "private func isPresetSpeaker" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ isPresetSpeaker() exists: $?"

# 2. fetchVoices() uses presetSpeakers
grep -q "Self.presetSpeakers.map" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ fetchVoices() updated: $?"

# 3. isVoiceAvailable() checks presets
grep -q "isPresetSpeaker(voiceId)" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ isVoiceAvailable() updated: $?"

# 4. File compiles
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Builds successfully: $?"
```

**Success**: All 4 commands return exit code 0

**Dependencies**: Sprint 1a.1 (needs presetSpeakers array)

**Rollback**: Revert methods if fails

---

### Sprint 1a.3: Audio Generation with Presets
**Model**: 🟡 Sonnet 4.5
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

**Scope**: Add audio generation for preset speakers

**Tasks**:

1. Add `generateWithPresetSpeaker()` method:
   ```swift
   private func generateWithPresetSpeaker(
       text: String,
       speakerName: String,
       language: String
   ) async throws -> Data {
       let model = try await modelManager.loadModel(.customVoice1_7B)

       guard let qwenModel = model as? Qwen3TTSModel else {
           throw VoxAltaError.modelNotAvailable(
               "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
           )
       }

       let audioArray = try await qwenModel.generate(
           text: text,
           voice: speakerName,
           refAudio: nil,
           refText: nil,
           language: language,
           generationParameters: GenerateParameters()
       )

       return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
   }
   ```

2. Update `generateAudio()` with dual-mode routing:
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

**Exit Criteria** (machine-verifiable):

```bash
# 1. generateWithPresetSpeaker() exists
grep -q "private func generateWithPresetSpeaker" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ generateWithPresetSpeaker() exists: $?"

# 2. generateAudio() calls it
grep -q "generateWithPresetSpeaker(" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ generateAudio() calls helper: $?"

# 3. Dual-mode routing exists
grep -q "if isPresetSpeaker(voiceId)" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ Dual-mode routing exists: $?"

# 4. File compiles
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Builds successfully: $?"
```

**Success**: All 4 commands return exit code 0

**Dependencies**: Sprint 1a.2 (needs isPresetSpeaker() and fetchVoices())

**Rollback**: Revert methods if fails

---

### Sprint 1b: Imports and Sendable Conformance
**Model**: 🟡 Sonnet 4.5
**Duration**: 12 turns (24% utilization)
**Time**: 16 min

**File**: `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift`

**Scope**: Add required imports and handle Sendable warnings

**Tasks**:

1. Add imports at top of file:
   ```swift
   import MLX
   import MLXAudioTTS
   import MLXLMCommon
   ```

2. Use `@preconcurrency` if Sendable warnings appear:
   ```swift
   @preconcurrency import MLX
   @preconcurrency import MLXAudioTTS
   ```

3. If build shows actor isolation warnings, mark public methods as `nonisolated`:
   ```swift
   nonisolated public func generateAudio(...)
   nonisolated public func fetchVoices(...)
   nonisolated public func isVoiceAvailable(...)
   ```

   **Pattern reference**: See `Sources/diga/DigaEngine.swift` (lines 45-67)
   **When to apply**: Only if build produces errors like "Call to actor-isolated method requires 'self' to be isolated"

**Exit Criteria** (machine-verifiable):

```bash
# 1. Build succeeds with zero warnings
WARNINGS=$(xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -i "warning" | wc -l | tr -d ' ')
test "$WARNINGS" -eq 0
echo "✓ Zero warnings: $?"

# 2. Required imports present
grep -q "import MLX" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ MLX import exists: $?"
grep -q "import MLXAudioTTS" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
echo "✓ MLXAudioTTS import exists: $?"

# 3. No Sendable conformance errors in build log
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "Sendable"
test $? -ne 0
echo "✓ No Sendable errors: $?"
```

**Success**: All 3 commands return exit code 0

**Dependencies**: Sprint 1a.3 (modifies same file)

**Rollback**: Revert imports if fails

---

### Sprint 2a: Core Voice Tests
**Model**: 🟡 Sonnet 4.5
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**File**: `Tests/SwiftVoxAltaTests/VoxAltaVoiceProviderTests.swift`

**Scope**: Write tests for voice listing operations (no audio generation yet)

**Tests**:

1. **testFetchVoicesReturnsPresetSpeakers()**:
   ```swift
   @Test("Fetch voices returns all 9 preset speakers")
   func testFetchVoicesReturnsPresetSpeakers() async throws {
       let provider = VoxAltaVoiceProvider()
       let voices = try await provider.fetchVoices(languageCode: "en")

       #expect(voices.count >= 9, "Should return at least 9 preset speakers")

       let presetIds = ["ryan", "aiden", "vivian", "serena", "uncle_fu", "dylan", "eric", "anna", "sohee"]
       for id in presetIds {
           #expect(voices.contains { $0.id == id }, "Missing preset speaker: \(id)")
       }
   }
   ```

2. **testIsVoiceAvailableForPresets()**:
   ```swift
   @Test("Preset speakers are always available")
   func testIsVoiceAvailableForPresets() async {
       let provider = VoxAltaVoiceProvider()

       let available = await provider.isVoiceAvailable(voiceId: "ryan")
       #expect(available == true, "Preset speaker 'ryan' should always be available")

       let unavailable = await provider.isVoiceAvailable(voiceId: "nonexistent_voice")
       #expect(unavailable == false, "Non-preset voice should not be available")
   }
   ```

3. **testDualModeRouting()**:
   ```swift
   @Test("Dual-mode routing: preset vs clone prompt")
   func testDualModeRouting() async throws {
       let provider = VoxAltaVoiceProvider()

       // Test clone prompt route (should throw since no voice loaded)
       await #expect(throws: VoxAltaError.self) {
           try await provider.generateAudio(
               text: "Clone test",
               voiceId: "custom_voice_123",
               languageCode: "en"
           )
       }
   }
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. Test file compiles
xcodebuild build-for-testing -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Test file compiles: $?"

# 2. All 3 tests pass
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testFetchVoicesReturnsPresetSpeakers \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testIsVoiceAvailableForPresets \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testDualModeRouting \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "Test Suite 'Selected tests' passed"
echo "✓ All 3 tests pass: $?"

# 3. Tests run in < 10 seconds (no model downloads)
time xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testFetchVoicesReturnsPresetSpeakers \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "Test Suite 'Selected tests' passed"
echo "✓ Fast execution (no model load): $?"
```

**Success**: All 3 commands return exit code 0

**Dependencies**: Sprints 1a.1, 1a.2, 1a.3, 1b (needs working VoxAltaVoiceProvider)

**Can run in parallel with**: Sprint 3a (different repos)

**Rollback**: Delete test file if fails

---

### Sprint 2b: Audio Generation Tests
**Model**: 🟡 Sonnet 4.5
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**File**: `Tests/SwiftVoxAltaTests/VoxAltaVoiceProviderTests.swift`

**Scope**: Write tests for audio generation (requires model download)

**Tests**:

1. **testGenerateAudioWithPresetSpeaker()**:
   ```swift
   @Test("Generate audio with preset speaker 'ryan'")
   func testGenerateAudioWithPresetSpeaker() async throws {
       let provider = VoxAltaVoiceProvider()
       let audio = try await provider.generateAudio(
           text: "Hello from Ryan",
           voiceId: "ryan",
           languageCode: "en"
       )

       #expect(audio.count > 44, "WAV should be larger than 44-byte header")

       // Validate WAV format
       let riff = String(data: audio[0..<4], encoding: .ascii)
       #expect(riff == "RIFF", "Should be WAV format (RIFF header)")
   }
   ```

2. **testGenerateAudioWithAllPresetSpeakers()**:
   ```swift
   @Test("Generate audio with all 9 preset speakers")
   func testGenerateAudioWithAllPresetSpeakers() async throws {
       let provider = VoxAltaVoiceProvider()
       let presetIds = ["ryan", "aiden", "vivian", "serena", "uncle_fu", "dylan", "eric", "anna", "sohee"]

       for id in presetIds {
           let audio = try await provider.generateAudio(
               text: "Testing voice \(id)",
               voiceId: id,
               languageCode: "en"
           )
           #expect(audio.count > 44, "Speaker \(id) should generate valid audio")
       }
   }
   ```

3. **testGenerateProcessedAudioDuration()**:
   ```swift
   @Test("Generated audio has expected duration")
   func testGenerateProcessedAudioDuration() async throws {
       let provider = VoxAltaVoiceProvider()
       let text = "This is a test sentence."

       let audio = try await provider.generateAudio(
           text: text,
           voiceId: "ryan",
           languageCode: "en"
       )

       // Parse WAV header to get duration
       let duration = try parsedWAVDuration(audio)

       // Expect ~1-3 seconds for a short sentence
       #expect(duration > 0.5, "Audio should be at least 0.5 seconds")
       #expect(duration < 10.0, "Audio should be less than 10 seconds for short text")
   }

   private func parsedWAVDuration(_ wavData: Data) throws -> Double {
       // Parse WAV header (44 bytes)
       guard wavData.count > 44 else { throw VoxAltaError.invalidAudioData }

       // Sample rate at bytes 24-27 (little-endian)
       let sampleRate = wavData[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }

       // Data chunk size at bytes 40-43 (little-endian)
       let dataSize = wavData[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }

       // Duration = dataSize / (sampleRate * channels * bytesPerSample)
       // For 16-bit mono: dataSize / (sampleRate * 1 * 2)
       return Double(dataSize) / Double(sampleRate * 2)
   }
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. All 3 tests pass
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testGenerateAudioWithPresetSpeaker \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testGenerateAudioWithAllPresetSpeakers \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testGenerateProcessedAudioDuration \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "Test Suite 'Selected tests' passed"
echo "✓ All 3 tests pass: $?"

# 2. Tests complete in < 90 seconds (includes model download on first run)
timeout 90s xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testGenerateAudioWithPresetSpeaker \
  CODE_SIGNING_ALLOWED=NO
echo "✓ Completes in time: $?"

# 3. No crashes or exceptions
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -qi "crashed\|exception"
test $? -ne 0
echo "✓ No crashes: $?"
```

**Success**: All 3 commands return exit code 0

**Dependencies**: Sprint 2a (validates foundation before expensive audio tests)

**Rollback**: Delete tests if fails

---

### Phase 2: Produciesta Integration (Sprints 3a - 5)

---

### Sprint 3a: Add Package Dependency
**Model**: 🟡 Sonnet 4.5
**Duration**: 10 turns (20% utilization)
**Time**: 13 min

**Files**: `../Produciesta/Package.swift`

**Scope**: Add SwiftVoxAlta package dependency to Produciesta

**Tasks**:

1. Add SwiftVoxAlta package dependency:
   ```swift
   // Package.swift
   dependencies: [
       .package(path: "../SwiftVoxAlta"),
       // ... other dependencies
   ],
   targets: [
       .target(
           name: "Produciesta",
           dependencies: [
               .product(name: "SwiftVoxAlta", package: "SwiftVoxAlta"),
               // ... other dependencies
           ]
       )
   ]
   ```

2. Build Produciesta to verify dependency resolves:
   ```bash
   cd ../Produciesta
   xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. SwiftVoxAlta in dependencies array
grep -q 'package(path: "../SwiftVoxAlta")' ../Produciesta/Package.swift
echo "✓ Package dependency exists: $?"

# 2. SwiftVoxAlta product in target dependencies
grep -q 'product(name: "SwiftVoxAlta"' ../Produciesta/Package.swift
echo "✓ Product dependency exists: $?"

# 3. Produciesta builds successfully
cd ../Produciesta && xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Produciesta builds: $?"

# 4. No package resolution errors
cd ../Produciesta && xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -qi "package resolution.*error"
test $? -ne 0
echo "✓ No resolution errors: $?"
```

**Success**: All 4 commands return exit code 0

**Dependencies**: Sprints 1a.1, 1a.2, 1a.3, 1b (needs working SwiftVoxAlta package)

**Can run in parallel with**: Sprint 2a, 2b (different repos)

**Rollback**: Remove dependency lines if fails

---

### Sprint 3a2.1: Provider Registration Discovery
**Model**: 🔴 Opus 4.6 (unfamiliar codebase exploration) ← **HIGH VALUE**
**Duration**: 10 turns (20% utilization)
**Time**: 15 min

**Files**: `../Produciesta` (read-only exploration)

**Scope**: Find where voice providers are registered (discovery ONLY, no changes)

**Why Opus**:
- Unfamiliar Produciesta codebase
- Need to find registration pattern by reading multiple files
- Wrong location = wasted implementation work in next sprint
- Opus's code understanding prevents misidentification

**Tasks**:

1. Search for existing registrations:
   ```bash
   cd ../Produciesta
   grep -r "register(provider:" . 2>/dev/null | tee /tmp/voxalta-register-search.txt
   grep -r "VoiceProviderRegistry" . 2>/dev/null | tee /tmp/voxalta-registry-search.txt
   grep -r "Apple.*TTS\|ElevenLabs" . 2>/dev/null | tee /tmp/voxalta-providers-search.txt
   ```

2. Read files containing registrations to understand pattern

3. Document findings in `/tmp/voxalta-registration-findings.md`:
   ```markdown
   # VoxAlta Registration Findings

   ## Registration File
   - Path: [full path to file]
   - Line: [line number]

   ## Registration Pattern
   - Function: [function name where registration happens]
   - Pattern: [exact code pattern, e.g., registry.register(provider: ...)]

   ## Existing Providers
   - Apple: [file:line]
   - ElevenLabs: [file:line]

   ## Registration Timing
   - [When registration happens: app startup, lazy init, etc.]
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. Findings document exists
test -f /tmp/voxalta-registration-findings.md
echo "✓ Findings document exists: $?"

# 2. Document contains registration file path
grep -q "Path:" /tmp/voxalta-registration-findings.md
echo "✓ File path documented: $?"

# 3. Document contains registration pattern
grep -q "Pattern:" /tmp/voxalta-registration-findings.md
echo "✓ Pattern documented: $?"

# 4. Search results captured
test -f /tmp/voxalta-register-search.txt
echo "✓ Search results saved: $?"

# 5. File path from findings actually exists
FILE_PATH=$(grep "Path:" /tmp/voxalta-registration-findings.md | cut -d: -f2- | xargs)
cd ../Produciesta && test -f "$FILE_PATH"
echo "✓ Registration file exists: $?"
```

**Success**: All 5 commands return exit code 0

**Dependencies**: Sprint 3a (needs Produciesta to build)

**Can start when**: Sprint 3a completes (overlaps with Sprint 2b)

**Rollback**: Delete findings files (no code changes)

---

### Sprint 3a2.2: Provider Registration Implementation
**Model**: 🟡 Sonnet 4.5 (path is known from discovery)
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**Files**: File from `/tmp/voxalta-registration-findings.md`

**Scope**: Register VoxAlta provider using discovered pattern

**Tasks**:

1. Read registration file path from findings:
   ```bash
   FILE_PATH=$(grep "Path:" /tmp/voxalta-registration-findings.md | cut -d: -f2- | xargs)
   echo "Registering in: $FILE_PATH"
   ```

2. Import SwiftVoxAlta in registration file:
   ```swift
   import SwiftVoxAlta
   ```

3. Register VoxAlta provider using discovered pattern:
   ```swift
   // Add adjacent to existing Apple/ElevenLabs registrations
   let voxAltaProvider = VoxAltaVoiceProvider()
   registry.register(provider: voxAltaProvider)
   ```

4. Add integration test:
   ```swift
   @Test("VoxAlta provider is registered")
   func testVoxAltaProviderRegistration() {
       let registry = VoiceProviderRegistry.shared
       let providers = registry.providers

       #expect(providers.contains { $0.providerId == "voxalta" },
               "VoxAlta provider should be registered")
   }
   ```

5. Add voice fetching test:
   ```swift
   @Test("Fetch VoxAlta voices from registry")
   func testFetchVoxAltaVoicesFromRegistry() async throws {
       let registry = VoiceProviderRegistry.shared
       guard let provider = registry.provider(for: "voxalta") else {
           Issue.record("VoxAlta provider not found in registry")
           return
       }

       let voices = try await provider.fetchVoices(languageCode: "en")
       #expect(voices.count >= 9, "Should return at least 9 preset speakers")
   }
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. Get registration file path
FILE_PATH=$(grep "Path:" /tmp/voxalta-registration-findings.md | cut -d: -f2- | xargs)

# 2. Import added to registration file
cd ../Produciesta && grep -q "import SwiftVoxAlta" "$FILE_PATH"
echo "✓ Import added: $?"

# 3. VoxAltaVoiceProvider instantiated
cd ../Produciesta && grep -q "VoxAltaVoiceProvider()" "$FILE_PATH"
echo "✓ Provider instantiated: $?"

# 4. Produciesta builds
cd ../Produciesta && xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Builds successfully: $?"

# 5. Registration test passes
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testVoxAltaProviderRegistration \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ Registration test passes: $?"

# 6. Voice fetching test passes
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testFetchVoxAltaVoicesFromRegistry \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ Voice fetching test passes: $?"
```

**Success**: All 6 commands return exit code 0

**Dependencies**: Sprint 3a2.1 (needs registration location)

**Rollback**: Revert import and registration if fails

---

### Sprint 3b.1: macOS App Integration
**Model**: 🟡 Sonnet 4.5
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**Files**: `../Produciesta/.../VoiceSelectionView.swift` (or equivalent UI)

**Scope**: macOS app ONLY (CLI is separate sprint)

**Tasks**:

1. Verify VoiceSelectionView exists:
   ```bash
   find ../Produciesta -name "*VoiceSelection*.swift" | head -1 | tee /tmp/voxalta-voice-ui-file.txt
   ```

2. Update voice dropdown to show VoxAlta provider:
   ```swift
   // Group voices by provider
   ForEach(groupedVoices, id: \.provider) { group in
       Section(header: Text(group.provider)) {
           ForEach(group.voices) { voice in
               Text("\(voice.name) - \(voice.description)")
           }
       }
   }
   ```

3. Add automated test:
   ```swift
   @Test("macOS: Voice selection includes VoxAlta provider")
   func testMacOSVoiceSelectionIncludesVoxAlta() async throws {
       let registry = VoiceProviderRegistry.shared
       let provider = try #require(registry.provider(for: "voxalta"),
                                   "VoxAlta provider not registered")
       let voices = try await provider.fetchVoices(languageCode: "en")

       // Verify provider is available for selection
       #expect(voices.count >= 9, "Should have 9 preset speakers")
       #expect(voices.first?.providerId == "voxalta", "Should be VoxAlta provider")

       // Verify voices can be used for generation
       let testVoice = try #require(voices.first)
       let audio = try await provider.generateAudio(
           text: "Test generation",
           voiceId: testVoice.id,
           languageCode: "en"
       )
       #expect(audio.count > 44, "Should generate valid audio")
   }
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. macOS app builds
cd ../Produciesta && xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ macOS app builds: $?"

# 2. Test passes
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testMacOSVoiceSelectionIncludesVoxAlta \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ macOS test passes: $?"

# 3. VoxAlta provider appears in registry
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testVoxAltaProviderRegistration \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ VoxAlta in registry: $?"

# 4. All 9 voices selectable
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testFetchVoxAltaVoicesFromRegistry \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ 9 voices available: $?"
```

**Success**: All 4 commands return exit code 0

**Dependencies**: Sprint 3a2.2 (needs provider registered)

**Rollback**: Revert UI changes if fails

---

### Sprint 3b.2: CLI Integration (OPTIONAL)
**Model**: 🟡 Sonnet 4.5
**Duration**: 10 turns (20% utilization) OR 0 turns if skipped
**Time**: 13 min OR 0 min

**Files**: `../Produciesta/CLI/main.swift` (if exists)

**Scope**: CLI ONLY (optional - skips if no CLI)

**Pre-check**:
```bash
# Check if CLI exists
test -f ../Produciesta/CLI/main.swift
if [ $? -ne 0 ]; then
  echo "CLI doesn't exist - SKIP this sprint"
  exit 0
fi
```

**Tasks** (only if pre-check passes):

1. Update CLI voice listing:
   ```swift
   // CLI should list VoxAlta in available providers
   let providers = VoiceProviderRegistry.shared.allProviders()
   for provider in providers {
       print("  - \(provider.name) (\(provider.type))")
   }
   ```

2. Add automated test:
   ```swift
   @Test("CLI: VoxAlta provider available for voice selection")
   func testCLIVoxAltaProviderAvailable() async throws {
       let registry = VoiceProviderRegistry.shared
       let providers = registry.allProviders()

       // Verify VoxAlta is in provider list
       #expect(providers.contains { $0.providerId == "voxalta" },
               "VoxAlta provider must be available in CLI")

       // Verify voices can be listed
       let provider = try #require(registry.provider(for: "voxalta"))
       let voices = try await provider.fetchVoices(languageCode: "en")
       #expect(voices.count >= 9, "CLI should access all 9 voices")
   }
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 0. Pre-check: CLI exists (if not, sprint succeeds immediately)
test -f ../Produciesta/CLI/main.swift
if [ $? -ne 0 ]; then
  echo "✓ CLI doesn't exist - sprint skipped successfully: 0"
  exit 0
fi

# 1. CLI builds
cd ../Produciesta && xcodebuild build -scheme ProduciestaCLI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ CLI builds: $?"

# 2. Test passes
cd ../Produciesta && xcodebuild test -scheme ProduciestaCLI -destination 'platform=macOS' \
  -only-testing:ProduciestaCLITests/testCLIVoxAltaProviderAvailable \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
echo "✓ CLI test passes: $?"
```

**Success**: CLI doesn't exist (skip) OR all tests pass

**Dependencies**: Sprint 3b.1 (macOS integration complete)

**Rollback**: Revert CLI changes if fails (or skip if no CLI)

---

### Sprint 4a: E2E Test Scaffold
**Model**: 🟡 Sonnet 4.5
**Duration**: 20 turns (40% utilization)
**Time**: 27 min

**Scope**: Write E2E test structure and AudioMetrics helper (NO EXECUTION)

**File**: `../Produciesta/Tests/.../E2EAudioGenerationTests.swift`

**Tasks**:

1. Create test file skeleton:
   ```swift
   import Testing
   import AVFoundation
   @testable import Produciesta
   @testable import SwiftVoxAlta

   @Suite("E2E Audio Generation")
   struct E2EAudioGenerationTests {
       // Tests will go here
   }
   ```

2. Write AudioMetrics helper:
   ```swift
   struct AudioMetrics {
       let sampleRate: Double
       let channelCount: Int
       let rms: Float
       let peak: Float
       let duration: Double
       let format: String
   }

   private func validateAudioQuality(fileURL: URL) throws -> AudioMetrics {
       let audioFile = try AVAudioFile(forReading: fileURL)
       let format = audioFile.processingFormat

       let buffer = AVAudioPCMBuffer(
           pcmFormat: format,
           frameCapacity: AVAudioFrameCount(audioFile.length)
       )!
       try audioFile.read(into: buffer)

       let rms = calculateRMS(buffer: buffer)
       let peak = calculatePeak(buffer: buffer)
       let duration = Double(audioFile.length) / format.sampleRate

       return AudioMetrics(
           sampleRate: format.sampleRate,
           channelCount: Int(format.channelCount),
           rms: rms,
           peak: peak,
           duration: duration,
           format: fileURL.pathExtension.uppercased()
       )
   }

   private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
       guard let floatData = buffer.floatChannelData?[0] else { return 0.0 }
       let frameCount = Int(buffer.frameLength)

       var sumSquares: Float = 0.0
       for i in 0..<frameCount {
           sumSquares += floatData[i] * floatData[i]
       }

       return sqrt(sumSquares / Float(frameCount))
   }

   private func calculatePeak(buffer: AVAudioPCMBuffer) -> Float {
       guard let floatData = buffer.floatChannelData?[0] else { return 0.0 }
       let frameCount = Int(buffer.frameLength)

       var peak: Float = 0.0
       for i in 0..<frameCount {
           peak = max(peak, abs(floatData[i]))
       }

       return peak
   }
   ```

3. Write E2E test structure (without execution):
   ```swift
   @Test("E2E: Generate podcast audio with VoxAlta voices")
   func testE2EGeneratePodcastWithVoxAltaVoices() async throws {
       // Setup: Create test podcast project
       let project = PodcastProject(name: "E2E Test")
       let character1 = Character(name: "Alice", voiceId: "ryan", providerId: "voxalta")
       let character2 = Character(name: "Bob", voiceId: "serena", providerId: "voxalta")
       project.characters = [character1, character2]

       let episode = Episode(
           lines: [
               Line(character: "Alice", text: "Hello, this is a test."),
               Line(character: "Bob", text: "Yes, this is a test of VoxAlta.")
           ]
       )

       // Execute: Generate audio for episode
       let audioFiles = try await project.generateAudio(for: episode)

       // Verify: 2 audio files generated
       #expect(audioFiles.count == 2, "Should generate 2 audio files")

       // Verify: Audio quality for each file
       for (index, audioFile) in audioFiles.enumerated() {
           // Check 1: Non-zero file size
           let fileSize = try FileManager.default.attributesOfItem(atPath: audioFile.url.path)[.size] as! UInt64
           #expect(fileSize > 44,
                   "Line \(index): File too small, got \(fileSize) bytes")

           // Check 2 & 3: Contains audio data and not silent
           let metrics = try validateAudioQuality(fileURL: audioFile.url)

           #expect(metrics.sampleRate == 24000, accuracy: 100,
                   "Line \(index): Sample rate should be ~24kHz")
           #expect(metrics.channelCount == 1,
                   "Line \(index): Should be mono")
           #expect(metrics.rms > 0.02,
                   "Line \(index): Audio too quiet (RMS: \(metrics.rms))")
           #expect(metrics.peak > 0.1,
                   "Line \(index): Audio too quiet (Peak: \(metrics.peak))")
           #expect(metrics.duration > 0.5,
                   "Line \(index): Duration too short (\(metrics.duration)s)")
           #expect(metrics.format == "WAV",
                   "Line \(index): Should be WAV format")
       }
   }
   ```

4. Build test (don't run yet):
   ```bash
   cd ../Produciesta
   xcodebuild build-for-testing -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. Test file compiles
cd ../Produciesta && xcodebuild build-for-testing -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
echo "✓ Test file compiles: $?"

# 2. AudioMetrics struct defined
cd ../Produciesta && grep -q "struct AudioMetrics" Tests/.../E2EAudioGenerationTests.swift
echo "✓ AudioMetrics defined: $?"

# 3. calculateRMS and calculatePeak helpers implemented
cd ../Produciesta && grep -q "func calculateRMS" Tests/.../E2EAudioGenerationTests.swift
echo "✓ calculateRMS exists: $?"
cd ../Produciesta && grep -q "func calculatePeak" Tests/.../E2EAudioGenerationTests.swift
echo "✓ calculatePeak exists: $?"

# 4. E2E test structure complete
cd ../Produciesta && grep -q "func testE2EGeneratePodcastWithVoxAltaVoices" Tests/.../E2EAudioGenerationTests.swift
echo "✓ E2E test structure exists: $?"
```

**Success**: All 5 commands return exit code 0

**Dependencies**: Sprint 3b.1 (needs macOS integration complete)

**Note**: This sprint writes code but doesn't execute. Sprint 4b will run and debug.

**Rollback**: Delete test file if fails

---

### Sprint 4b: E2E Validation and Debugging (BOUNDED)
**Model**: 🔴 Opus 4.6 (E2E debugging) ← **HIGH VALUE**
**Duration**: 20 turns MAX (40% utilization)
**Time**: 30 min

**Scope**: Execute E2E test and debug failures (max 20 turns, then STOP)

**Why Opus**:
- E2E integration across two codebases (VoxAlta + Produciesta)
- Complex failure modes (audio generation, SwiftData, format issues)
- Debugging requires deep reasoning about system interactions
- Wrong fix = wasted debugging cycles
- Opus prevents misdiagnosis

**Tasks**:

1. Run E2E test (turn 1):
   ```bash
   cd ../Produciesta
   xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
     -only-testing:E2EAudioGenerationTests/testE2EGeneratePodcastWithVoxAltaVoices \
     CODE_SIGNING_ALLOWED=NO | tee /tmp/e2e-test-output.txt
   ```

2. If test passes → **DONE** (exit immediately)

3. If test fails → Debug (turns 2-20):
   - Analyze failure mode from output
   - Document in `/tmp/e2e-debug-log.md`:
     ```markdown
     ## Turn N: [Issue Description]
     - **Problem**: [what failed]
     - **Hypothesis**: [why it might have failed]
     - **Fix attempted**: [what was changed]
     - **Result**: [pass/fail]
     ```
   - Attempt fix
   - Re-run test
   - Repeat until turn 20

4. If still failing at turn 20 → **STOP** and create issue document:
   ```bash
   cat > /tmp/e2e-failure-report.md << 'EOF'
   # E2E Test Failure Report

   ## Status
   FAILED after 20 turns

   ## Failure Mode
   [Last error message from test]

   ## Attempted Fixes
   [Summary of all fixes attempted - read from debug log]

   ## Next Steps
   1. Review debug log: /tmp/e2e-debug-log.md
   2. Consider rollback to Sprint 3b.1
   3. File issue for deeper investigation
   4. Possible root causes:
      - [List hypotheses]

   ## Rollback Plan
   ```bash
   cd ../Produciesta
   git revert HEAD~N  # Revert to Sprint 3b.1
   ```
   EOF
   ```

**Exit Criteria** (machine-verifiable):

```bash
# SUCCESS CRITERIA (either):

# Option A: Test passes
cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:E2EAudioGenerationTests/testE2EGeneratePodcastWithVoxAltaVoices \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "Test Suite.*passed"
echo "✓ E2E test passes: $?"

# Option B: Reached turn limit and documented failure
test -f /tmp/e2e-failure-report.md && grep -q "FAILED after 20 turns" /tmp/e2e-failure-report.md
echo "✓ Failure documented (reached turn limit): $?"

# VALIDATION (if Option A - test passes):
# 1. All audio files have non-zero size
#    [Verified by test assertions]

# 2. All audio files contain valid data
#    [Verified by test assertions: RMS > 0.02, Peak > 0.1]

# 3. Test completes in < 120 seconds
timeout 120s cd ../Produciesta && xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:E2EAudioGenerationTests/testE2EGeneratePodcastWithVoxAltaVoices \
  CODE_SIGNING_ALLOWED=NO
echo "✓ Completes in time: $?"
```

**Success**: Test passes OR failure documented (turn 20)

**"Audio plays correctly" is defined as**:
1. Non-zero file size (> 44 bytes minimum for WAV header)
2. Contains valid audio data (WAV format, readable by AVAudioFile)
3. Not silent (RMS > 0.02 and Peak > 0.1)

**Dependencies**: Sprint 4a (needs test scaffold written)

**Rollback**: If fails after 20 turns, revert to Sprint 3b.1 state

---

### Sprint 5: Documentation
**Model**: 🟢 Haiku 4.5 (templated content)
**Duration**: 15 turns (30% utilization)
**Time**: 20 min

**Files**:
- `README.md`
- `AGENTS.md`
- `docs/PRODUCIESTA_INTEGRATION.md` (new)

**Scope**: Update documentation with Produciesta integration examples

**Tasks**:

1. **Update README.md** - Add Produciesta integration section:
   ```markdown
   ## Produciesta Integration

   VoxAlta provides 9 high-quality CustomVoice preset speakers for character voice assignment:

   - **Ryan**: Dynamic male voice with strong rhythmic drive
   - **Aiden**: Sunny American male voice with clear midrange
   - **Vivian**: Bright, slightly edgy young Chinese female voice
   - **Serena**: Warm, gentle young Chinese female voice
   - **Uncle Fu**: Seasoned Chinese male voice with low, mellow timbre
   - **Dylan**: Youthful Beijing male voice with clear timbre
   - **Eric**: Lively Chengdu male voice with husky brightness
   - **Anna**: Playful Japanese female voice with light timbre
   - **Sohee**: Warm Korean female voice with rich emotion

   ### Quick Start

   ```swift
   import SwiftVoxAlta

   let provider = VoxAltaVoiceProvider()
   let audio = try await provider.generateAudio(
       text: "Hello from VoxAlta",
       voiceId: "ryan",
       languageCode: "en"
   )
   ```
   ```

2. **Update AGENTS.md** - Document VoiceProvider implementation:
   ```markdown
   ## VoiceProvider Implementation

   VoxAltaVoiceProvider conforms to SwiftHablare's VoiceProvider protocol:

   - `fetchVoices(languageCode:)` → Returns 9 preset speakers + cached custom voices
   - `generateAudio(text:voiceId:languageCode:)` → Dual-mode routing (presets or clone prompts)
   - `isVoiceAvailable(voiceId:)` → Presets always available, custom voices checked in cache

   ### Dual-Mode Routing

   1. **Preset speakers** (fast path): Direct CustomVoice model generation
   2. **Clone prompts** (fallback): For custom voices loaded via loadVoice()
   ```

3. **Create docs/PRODUCIESTA_INTEGRATION.md**:
   ```markdown
   # Produciesta Integration Guide

   [Complete integration documentation with:
    - Prerequisites
    - Integration steps
    - Performance notes
    - Troubleshooting]
   ```

**Exit Criteria** (machine-verifiable):

```bash
# 1. All 3 files exist
test -f README.md && test -f AGENTS.md && test -f docs/PRODUCIESTA_INTEGRATION.md
echo "✓ All files exist: $?"

# 2. README contains Produciesta Integration section
grep -q "Produciesta Integration" README.md
echo "✓ README updated: $?"

# 3. AGENTS contains VoiceProvider section
grep -q "VoiceProvider Implementation" AGENTS.md
echo "✓ AGENTS updated: $?"

# 4. Integration doc exists and is substantial
SIZE=$(wc -c < docs/PRODUCIESTA_INTEGRATION.md)
test "$SIZE" -gt 500
echo "✓ Integration doc substantial (>500 bytes): $?"

# 5. All 9 voices documented in README
COUNT=$(grep -c "Ryan\|Aiden\|Vivian\|Serena\|Uncle Fu\|Dylan\|Eric\|Anna\|Sohee" README.md)
test "$COUNT" -ge 9
echo "✓ All 9 voices documented: $?"
```

**Success**: All 5 commands return exit code 0

**Dependencies**: Sprint 4b (documents working implementation or failure)

**Rollback**: Revert documentation if fails

---

## Success Criteria

**All criteria are machine-verifiable** (run this verification script after execution):

```bash
#!/bin/bash
# verify-integration.sh - Run after all sprints complete

echo "=== VoxAlta → Produciesta Integration Verification ==="

# 1. VoxAlta builds without warnings
cd /Users/stovak/Projects/SwiftVoxAlta
WARNINGS=$(xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -i warning | wc -l | tr -d ' ')
test "$WARNINGS" -eq 0 && echo "✓ VoxAlta builds without warnings" || echo "✗ Build has warnings"

# 2. fetchVoices returns 9 preset speakers
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testFetchVoicesReturnsPresetSpeakers \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
test $? -eq 0 && echo "✓ fetchVoices returns 9 presets" || echo "✗ fetchVoices test failed"

# 3. All 9 preset speakers generate valid audio
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testGenerateAudioWithAllPresetSpeakers \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
test $? -eq 0 && echo "✓ All 9 speakers generate audio" || echo "✗ Audio generation test failed"

# 4. Dual-mode routing works
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS' \
  -only-testing:SwiftVoxAltaTests/VoxAltaVoiceProviderTests/testDualModeRouting \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
test $? -eq 0 && echo "✓ Dual-mode routing works" || echo "✗ Routing test failed"

# 5. Produciesta builds with VoxAlta dependency
cd /Users/stovak/Projects/Produciesta
xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "BUILD SUCCEEDED"
test $? -eq 0 && echo "✓ Produciesta builds" || echo "✗ Produciesta build failed"

# 6. VoxAlta provider in registry
xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:ProduciestaTests/testVoxAltaProviderRegistration \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
test $? -eq 0 && echo "✓ VoxAlta in registry" || echo "✗ Registration test failed"

# 7. E2E test passes (audio plays correctly)
xcodebuild test -scheme Produciesta -destination 'platform=macOS' \
  -only-testing:E2EAudioGenerationTests/testE2EGeneratePodcastWithVoxAltaVoices \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -q "passed"
test $? -eq 0 && echo "✓ E2E test passes (audio plays correctly)" || echo "✗ E2E test failed"

# 8. Documentation files exist
cd /Users/stovak/Projects/SwiftVoxAlta
test -f README.md && test -f AGENTS.md && test -f docs/PRODUCIESTA_INTEGRATION.md
test $? -eq 0 && echo "✓ Documentation complete" || echo "✗ Missing documentation"

echo "=== Verification Complete ==="
```

---

## Execution Timeline (V4 - Atomic Sprints)

**Total**: 15 sprints, ~165 turns, ~3.5 hours

### Sequential Sprints (Sprints 1a.1 - 1b)
```
Period 1: Sprint 1a.1 (Preset Data)                  [5 turns,  7 min]
Period 2: Sprint 1a.2 (Voice Listing)                [10 turns, 13 min]
Period 3: Sprint 1a.3 (Audio Generation)             [15 turns, 20 min]
Period 4: Sprint 1b (Imports/Sendable)               [12 turns, 16 min]
```

### Parallel Phase 1 (Sprints 2a, 2b, 3a)
```
Period 5: Sprint 3a || Sprint 2a                     [15 turns, 20 min]
          ├─ Sprint 3a (Package Dependency)          [10 turns, 13 min] ← finishes first
          └─ Sprint 2a (Core Voice Tests)            [15 turns, 20 min] ← continues

Period 6: Sprint 3a2.1 || Sprint 2a (continues)      [10 turns, 15 min]
          ├─ Sprint 3a2.1 (Discovery, Opus)          [10 turns, 15 min] ← starts when 3a done
          └─ Sprint 2a (Core Voice Tests)            [5 turns remain]   ← finishes

Period 7: Sprint 2b || Sprint 3a2.1 (continues)      [10 turns, 15 min]
          ├─ Sprint 2b (Audio Tests)                 [15 turns, 20 min] ← starts when 2a done
          └─ Sprint 3a2.1 finishes
```

### Parallel Phase 2 (Sprints 2b, 3a2.2)
```
Period 8: Sprint 2b (continues) || Sprint 3a2.2      [15 turns, 20 min]
          ├─ Sprint 2b (Audio Tests)                 [5 turns remain]   ← finishes
          └─ Sprint 3a2.2 (Registration, Sonnet)     [15 turns, 20 min] ← continues
```

### Sequential Sprints (Sprints 3b.1 - 5)
```
Period 9:  Sprint 3b.1 (macOS Integration)           [15 turns, 20 min]
Period 10: Sprint 3b.2 (CLI, optional)               [10 turns, 13 min] OR [0 if skipped]
Period 11: Sprint 4a (E2E Scaffold)                  [20 turns, 27 min]
Period 12: Sprint 4b (E2E Validation, Opus)          [20 turns, 30 min]
Period 13: Sprint 5 (Documentation, Haiku)           [15 turns, 20 min]
```

**Parallelism Summary**:
- Periods 5-8: 30 turns of parallel work (2 overlapping phases)
- Total time saved: ~40 minutes vs sequential
- Total: ~3.5 hours (vs ~4+ hours sequential)

---

## Dependencies Graph (V4)

```
Sprint 1a.1 (Data)
  └─→ Sprint 1a.2 (Listing)
        └─→ Sprint 1a.3 (Generation)
              └─→ Sprint 1b (Imports)
                    ├─→ Sprint 2a (Core Tests)           ┐
                    │     └─→ Sprint 2b (Audio Tests)    │ Parallel
                    └─→ Sprint 3a (Package)              │ Phase 1
                          └─→ Sprint 3a2.1 (Discovery)   ┘
                                └─→ Sprint 3a2.2 (Registration)
                                      └─→ Sprint 3b.1 (macOS)
                                            └─→ Sprint 3b.2 (CLI, optional)
                                                  └─→ Sprint 4a (E2E Scaffold)
                                                        └─→ Sprint 4b (E2E Validation)
                                                              └─→ Sprint 5 (Docs)
```

**Key Optimization**: Sprints 2a/2b and 3a/3a2.1/3a2.2 run in parallel (different repos)

---

## Changes from V3 → V4

### Sprint Structure
- ✅ Split Sprint 1a → 1a.1, 1a.2, 1a.3 (30 turns → 5 + 10 + 15 = 30 turns, safer)
- ✅ Split Sprint 2 → 2a, 2b (28 turns → 15 + 15 = 30 turns, batched tests)
- ✅ Split Sprint 3a2 → 3a2.1 (discovery), 3a2.2 (implementation) (25 turns → 10 + 15 = 25 turns)
- ✅ Split Sprint 3b → 3b.1 (macOS), 3b.2 (CLI, optional) (20 turns → 15 + 10 = 25 turns)
- ✅ Added turn limit to Sprint 4b (max 20 turns, document and stop if failing)

### Atomicity Improvements
- Each sprint now has 1-2 related tasks (vs 4-6 in V3)
- Smaller rollback units
- Clear success/failure points
- No unbounded exploration or debugging

### Testability Improvements
- All exit criteria have exact bash commands
- Success measured by exit codes (0 = pass)
- Discovery outputs to files (`/tmp/voxalta-*.txt`)
- Debug logs preserved (`/tmp/e2e-debug-log.md`)
- Verification script provided (`verify-integration.sh`)

### Model Usage
- Same as V3: Opus for discovery/debugging, Sonnet for development, Haiku for docs
- But discovery is now separate sprint (3a2.1), so cheaper implementation in 3a2.2

### Total Effort
- **V3**: 9 sprints, 152 turns
- **V4**: 15 sprints, ~165 turns (8% more turns, but much safer)
- Benefits: Atomic, testable, bounded, recoverable

---

## Rollback Plan

If integration fails, rollback is granular:

### Rollback by Sprint

```bash
# Rollback Sprint 1a.1 (just delete array)
git diff Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
git checkout Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift

# Rollback Sprint 1a.2 (revert methods)
git diff Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
git checkout Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift

# Rollback Sprint 3a2.2 (revert registration)
cd ../Produciesta
FILE=$(grep "Path:" /tmp/voxalta-registration-findings.md | cut -d: -f2- | xargs)
git diff "$FILE"
git checkout "$FILE"

# Rollback all VoxAlta changes
cd /Users/stovak/Projects/SwiftVoxAlta
git log --oneline | grep "Sprint 1"
git revert <commit-hash>

# Rollback all Produciesta changes
cd /Users/stovak/Projects/Produciesta
git log --oneline | grep "Sprint 3"
git revert <commit-hash>
```

### Fallback Strategy

If full rollback needed:
1. Remove VoxAlta from Produciesta Package.swift
2. Revert VoxAltaVoiceProvider to pre-sprint state
3. Use existing providers (Apple, ElevenLabs)
4. File issues with findings for future work

---

**Status**: ✅ **READY FOR EXECUTION (V4 - Atomic & Testable)**

**Next Step**: Execute Sprint 1a.1 (Add Preset Speaker Data)

```bash
# Start execution
cd /Users/stovak/Projects/SwiftVoxAlta
# Execute Sprint 1a.1...
```
