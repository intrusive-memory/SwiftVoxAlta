# Audio Generation Integration Test — Execution Plan

## Overview

Add a comprehensive integration test suite that spawns the `diga` binary, generates audio files, and validates:
1. File existence and non-zero size
2. Valid audio format headers (RIFF/WAVE)
3. Audio type matches expected format and extension
4. Audio contains non-silence (detectable signal level)

This test complements the existing CI bash-based audio validation with Swift-native testing using AVFoundation for deep audio analysis.

---

## Objectives

1. **Binary Execution**: Spawn the `diga` binary as a subprocess and generate audio to a temp file
2. **File Validation**: Verify the output file exists and has a reasonable size (> 44 bytes for WAV header)
3. **Format Validation**: Read the audio file using AVAudioFile and verify format matches expectations
4. **Type Validation**: Ensure audio format (WAV/AIFF/M4A) matches the file extension used
5. **Silence Detection**: Analyze PCM samples to ensure audio is not silent (RMS > threshold)
6. **Error Handling**: Verify graceful failure when binary is not built or invalid arguments are provided

---

## Success Criteria

### Primary Success Criteria

- [ ] Test successfully spawns `diga` binary from `./bin/diga` or built location
- [ ] Generated WAV file exists at specified path
- [ ] File size is > 44 bytes (minimum WAV header size)
- [ ] RIFF/WAVE headers are present and valid
- [ ] AVAudioFile can read the file without errors
- [ ] Audio format is Linear PCM, 24kHz, mono, 16-bit
- [ ] PCM samples contain non-zero values (not silence)
- [ ] RMS level of audio is above threshold (e.g., > 0.01)
- [ ] Peak amplitude is above threshold (e.g., > 0.1)

### Secondary Success Criteria

- [ ] Test works with different output formats (WAV, AIFF, M4A)
- [ ] Test validates format-specific headers (RIFF for WAV, FORM for AIFF, ftyp for M4A)
- [ ] Test properly cleans up temp files after execution
- [ ] Test provides clear error messages when validation fails
- [ ] Test is fast enough for CI (< 30 seconds on CI runner with model download)

---

## Test Structure

### Location

Add to: `Tests/DigaTests/DigaCLIIntegrationTests.swift`

### Test Suite Name

`@Suite("CLI Audio Generation Integration Tests")`

### Test Cases

1. **Basic WAV Generation and Validation**
   - `@Test("diga generates valid WAV file with audio data")`
   - Spawns diga with `-o /tmp/test.wav "Hello world"`
   - Validates all success criteria above

2. **AIFF Format Generation**
   - `@Test("diga generates valid AIFF file when specified")`
   - Spawns diga with `-o /tmp/test.aiff "Test audio"`
   - Validates FORM/AIFF headers

3. **M4A Format Generation**
   - `@Test("diga generates valid M4A file when specified")`
   - Spawns diga with `-o /tmp/test.m4a "Test audio"`
   - Validates M4A container format

4. **Silence Detection Works**
   - `@Test("Test correctly identifies silence (negative test)")`
   - Manually creates a WAV file with all-zero samples
   - Validates that the silence detection logic correctly identifies it as silent

5. **Binary Not Found Handling**
   - `@Test("Test fails gracefully when diga binary is not found")`
   - Attempts to run non-existent binary path
   - Validates error handling

---

## Implementation Details

### 1. Binary Spawning

```swift
/// Helper to spawn the diga binary and return the process result.
private func runDiga(args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
    let process = Process()

    // Try both ./bin/diga (release build) and derived data build location
    let binaryPaths = [
        "./bin/diga",
        "./.build/debug/diga",
        "./.build/release/diga"
    ]

    guard let binaryPath = binaryPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        throw TestError.binaryNotFound("diga binary not found at any expected location")
    }

    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return (
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}
```

### 2. File Validation

```swift
/// Validate that a file exists and has non-zero size.
private func validateFileExists(path: String, minSize: Int = 44) throws {
    guard FileManager.default.fileExists(atPath: path) else {
        throw TestError.fileNotFound("Audio file not created at \(path)")
    }

    let url = URL(fileURLWithPath: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let fileSize = attributes[.size] as? Int, fileSize > minSize else {
        throw TestError.invalidFile("File size (\(attributes[.size] ?? 0)) is too small (expected > \(minSize))")
    }
}
```

### 3. Format Validation

```swift
/// Validate audio file format using AVAudioFile.
private func validateAudioFormat(path: String, expectedFormat: AudioFormat) throws -> AVAudioFile {
    let url = URL(fileURLWithPath: path)
    let audioFile = try AVAudioFile(forReading: url)

    let format = audioFile.processingFormat

    // Validate sample rate (expected: 24000 Hz)
    guard format.sampleRate == 24000 else {
        throw TestError.invalidFormat("Expected 24kHz, got \(format.sampleRate)Hz")
    }

    // Validate channel count (expected: 1 = mono)
    guard format.channelCount == 1 else {
        throw TestError.invalidFormat("Expected mono (1 channel), got \(format.channelCount) channels")
    }

    // Validate it's PCM format (for WAV/AIFF)
    if expectedFormat == .wav || expectedFormat == .aiff {
        guard format.commonFormat == .pcmFormatInt16 || format.commonFormat == .pcmFormatFloat32 else {
            throw TestError.invalidFormat("Expected PCM format, got \(format.commonFormat)")
        }
    }

    return audioFile
}
```

### 4. Header Validation

```swift
/// Validate audio file magic bytes/headers.
private func validateAudioHeaders(path: String, expectedFormat: AudioFormat) throws {
    let url = URL(fileURLWithPath: path)
    let fileData = try Data(contentsOf: url)

    guard fileData.count >= 12 else {
        throw TestError.invalidFile("File too small to contain valid headers")
    }

    switch expectedFormat {
    case .wav:
        // Check for "RIFF" at offset 0
        let riff = String(data: fileData[0..<4], encoding: .ascii)
        guard riff == "RIFF" else {
            throw TestError.invalidFormat("Missing RIFF header (got: \(riff ?? "nil"))")
        }

        // Check for "WAVE" at offset 8
        let wave = String(data: fileData[8..<12], encoding: .ascii)
        guard wave == "WAVE" else {
            throw TestError.invalidFormat("Missing WAVE format marker (got: \(wave ?? "nil"))")
        }

    case .aiff:
        // Check for "FORM" at offset 0
        let form = String(data: fileData[0..<4], encoding: .ascii)
        guard form == "FORM" else {
            throw TestError.invalidFormat("Missing FORM header (got: \(form ?? "nil"))")
        }

        // Check for "AIFF" at offset 8
        let aiff = String(data: fileData[8..<12], encoding: .ascii)
        guard aiff == "AIFF" else {
            throw TestError.invalidFormat("Missing AIFF format marker (got: \(aiff ?? "nil"))")
        }

    case .m4a:
        // M4A files start with ftyp box (offset 4-8)
        let ftyp = String(data: fileData[4..<8], encoding: .ascii)
        guard ftyp == "ftyp" else {
            throw TestError.invalidFormat("Missing ftyp box for M4A (got: \(ftyp ?? "nil"))")
        }
    }
}
```

### 5. Silence Detection

```swift
/// Detect if audio contains only silence (all samples near zero).
private func validateNotSilence(audioFile: AVAudioFile, threshold: Float = 0.01) throws {
    let format = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw TestError.invalidFile("Could not allocate PCM buffer")
    }

    try audioFile.read(into: buffer)

    guard let floatData = buffer.floatChannelData else {
        throw TestError.invalidFile("Could not access float channel data")
    }

    // Calculate RMS (root mean square) level
    var sumSquares: Float = 0.0
    var peakAmplitude: Float = 0.0

    for frame in 0..<Int(buffer.frameLength) {
        let sample = floatData[0][frame]
        sumSquares += sample * sample
        peakAmplitude = max(peakAmplitude, abs(sample))
    }

    let rms = sqrt(sumSquares / Float(buffer.frameLength))

    print("Audio analysis: RMS=\(rms), Peak=\(peakAmplitude), Frames=\(buffer.frameLength)")

    // Verify RMS is above threshold
    guard rms > threshold else {
        throw TestError.silenceDetected("Audio RMS (\(rms)) is below threshold (\(threshold))")
    }

    // Verify peak amplitude is reasonable (should be > 0.1 for speech)
    guard peakAmplitude > 0.1 else {
        throw TestError.silenceDetected("Audio peak amplitude (\(peakAmplitude)) is too low")
    }
}
```

### 6. Error Types

```swift
enum TestError: Error, LocalizedError {
    case binaryNotFound(String)
    case fileNotFound(String)
    case invalidFile(String)
    case invalidFormat(String)
    case silenceDetected(String)
    case processError(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let detail): return "Binary not found: \(detail)"
        case .fileNotFound(let detail): return "File not found: \(detail)"
        case .invalidFile(let detail): return "Invalid file: \(detail)"
        case .invalidFormat(let detail): return "Invalid format: \(detail)"
        case .silenceDetected(let detail): return "Silence detected: \(detail)"
        case .processError(let detail): return "Process error: \(detail)"
        }
    }
}
```

---

## Test Implementation Sequence

### Phase 1: Basic WAV Test (Sprint 1)

**Goal**: Get basic end-to-end test working with WAV format

**Tasks**:
1. Add `TestError` enum to `DigaCLIIntegrationTests.swift`
2. Implement `runDiga()` helper function
3. Implement `validateFileExists()` helper
4. Implement `validateAudioHeaders()` helper for WAV
5. Write basic test: "diga generates valid WAV file with audio data"
   - Create temp output path
   - Run `./bin/diga --model 0.6b -o /tmp/test.wav "Hello world"`
   - Validate file exists and size > 44 bytes
   - Validate RIFF/WAVE headers
   - Clean up temp file
6. Run test locally, verify it passes
7. Update test to properly handle cleanup (defer)

**Success Criteria**:
- Test passes locally when diga binary is built
- Test properly cleans up temp files
- Test provides clear error messages on failure

### Phase 2: AVFoundation Validation (Sprint 2)

**Goal**: Add deep audio format validation using AVFoundation

**Tasks**:
1. Add AVFoundation import to test file
2. Implement `validateAudioFormat()` helper
3. Update basic test to validate audio format properties
   - Sample rate = 24000 Hz
   - Channel count = 1 (mono)
   - Format = PCM Int16 or Float32
4. Run test, verify AVAudioFile can read diga output
5. Debug any format mismatches

**Success Criteria**:
- AVAudioFile successfully reads diga-generated WAV files
- All format properties match expectations

### Phase 3: Silence Detection (Sprint 3)

**Goal**: Verify generated audio contains non-silence

**Tasks**:
1. Implement `validateNotSilence()` helper
2. Add RMS calculation logic
3. Add peak amplitude calculation
4. Determine appropriate thresholds (start conservative)
   - RMS threshold: 0.01
   - Peak threshold: 0.1
5. Update basic test to include silence validation
6. Create negative test with all-zero WAV to verify detection works
7. Tune thresholds if needed based on actual diga output

**Success Criteria**:
- Silence detection correctly identifies real audio
- Silence detection correctly identifies all-zero audio
- Thresholds are tuned to avoid false positives/negatives

### Phase 4: Multi-Format Support (Sprint 4)

**Goal**: Add tests for AIFF and M4A formats

**Tasks**:
1. Extend `validateAudioHeaders()` to support AIFF and M4A
2. Write test: "diga generates valid AIFF file when specified"
   - Run with `-o /tmp/test.aiff`
   - Validate FORM/AIFF headers
   - Validate format with AVAudioFile
   - Validate not silence
3. Write test: "diga generates valid M4A file when specified"
   - Run with `-o /tmp/test.m4a`
   - Validate ftyp box
   - Validate format with AVAudioFile
   - Validate not silence
4. Run all format tests, ensure they pass

**Success Criteria**:
- All three format tests pass (WAV, AIFF, M4A)
- Format-specific headers are correctly validated

### Phase 5: Error Handling and Robustness (Sprint 5)

**Goal**: Add negative tests and edge case handling

**Tasks**:
1. Write test: "Test fails gracefully when diga binary is not found"
   - Temporarily rename binary
   - Verify test throws appropriate error
   - Restore binary
2. Add timeout handling to `runDiga()` (30 second timeout)
3. Add test for invalid arguments (expect non-zero exit code)
4. Add test for empty text (should generate silence or minimal audio)
5. Verify all tests clean up temp files even on failure

**Success Criteria**:
- Negative tests pass and provide clear error messages
- No temp files left behind after test runs
- Tests complete within reasonable time (< 30s each)

### Phase 6: CI Integration (Sprint 6)

**Goal**: Ensure tests run properly in CI environment

**Tasks**:
1. Update `.github/workflows/tests.yml` to run these tests
2. Add model caching for faster CI runs (already exists)
3. Verify tests pass in CI with cold cache
4. Verify tests pass in CI with warm cache
5. Add artifact upload for generated audio files (for debugging)
6. Tune timeouts for CI environment if needed

**Success Criteria**:
- Tests pass in CI with both cold and warm cache
- CI run time is acceptable (< 5 minutes for audio tests)
- Artifacts are properly uploaded on failure

---

## Edge Cases and Considerations

### Model Download Handling

**Issue**: First run requires downloading 2.4GB model
**Solution**:
- CI already caches `~/Library/SharedModels`
- Tests should use `--model 0.6b` (smaller, faster)
- Add timeout of 300 seconds for first run
- Subsequent runs will be fast (model cached)

### Binary Build Location

**Issue**: Binary location varies (./bin/diga vs ./.build/debug/diga)
**Solution**:
- Check multiple locations in `runDiga()` helper
- Provide clear error if binary not found at any location

### Temp File Cleanup

**Issue**: Tests must clean up temp files even on failure
**Solution**:
- Always use `defer { try? FileManager.default.removeItem(at: tempURL) }`
- Use unique temp file names (UUID-based)
- Use `/tmp/` directory which OS cleans periodically

### RMS Threshold Tuning

**Issue**: Thresholds for silence detection may need adjustment
**Solution**:
- Start conservative (RMS > 0.01, Peak > 0.1)
- Print actual RMS/Peak values in test output
- Tune based on empirical results from diga output
- Document threshold rationale in test comments

### AVFoundation Format Differences

**Issue**: AVAudioFile may report format differently than expected
**Solution**:
- Accept both `.pcmFormatInt16` and `.pcmFormatFloat32`
- Focus on sample rate and channel count as primary checks
- Log actual format for debugging

---

## Dependencies

### Existing Code

- `Sources/diga/AudioFileWriter.swift` — Format definitions and writing logic
- `Sources/diga/DigaCommand.swift` — CLI argument parsing
- `Sources/diga/DigaEngine.swift` — Audio synthesis engine
- `Tests/DigaTests/DigaAudioFileWriterTests.swift` — Existing audio format tests

### System Frameworks

- `AVFoundation` — For AVAudioFile and PCM buffer analysis
- `Foundation` — For Process spawning and file management

### Build Dependencies

- Diga binary must be built (`make release` or `make build`)
- Models must be available (downloaded via first run or cache)

---

## Testing Plan

### Local Testing

```bash
# Build release binary first
make release

# Run just the audio generation tests
xcodebuild test \
  -scheme SwiftVoxAlta-Package \
  -destination 'platform=macOS' \
  -only-testing:DigaTests/CLIAudioGenerationTests
```

### CI Testing

Tests will run as part of existing `audio-integration` job in `.github/workflows/tests.yml`.

No changes needed to CI workflow — these tests supplement the existing bash-based validation.

---

## Success Metrics

### Code Coverage

- [ ] All helper functions have unit tests
- [ ] All three formats (WAV, AIFF, M4A) are tested
- [ ] Positive and negative test cases exist
- [ ] Edge cases are covered

### Quality Metrics

- [ ] Tests run in < 30 seconds locally (with warm cache)
- [ ] Tests run in < 45 seconds in CI (with warm cache)
- [ ] Zero false positives in 100 consecutive runs
- [ ] Clear error messages for all failure modes

### Documentation

- [ ] Test functions have clear doc comments
- [ ] Helper functions are documented
- [ ] Error messages are actionable
- [ ] Threshold values are documented with rationale

---

## Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Model download timeout in CI | High | Medium | Use model caching, increase timeout to 300s |
| Flaky RMS thresholds | Medium | Low | Conservative thresholds, print actual values |
| Binary not found in tests | High | Low | Check multiple paths, clear error messages |
| AVFoundation format mismatch | Medium | Low | Accept multiple PCM formats, focus on sample rate |
| Temp file cleanup failure | Low | Low | Use defer, unique names, /tmp directory |
| CI timeout (45 min) | Medium | Low | Use smaller model (0.6b), optimize cache |

---

## Rollout Plan

### Week 1
- Implement Phase 1 (Basic WAV Test)
- Local testing and debugging
- Code review

### Week 2
- Implement Phase 2 (AVFoundation Validation)
- Implement Phase 3 (Silence Detection)
- Local testing and tuning

### Week 3
- Implement Phase 4 (Multi-Format Support)
- Implement Phase 5 (Error Handling)
- Integration testing

### Week 4
- Implement Phase 6 (CI Integration)
- Final testing and documentation
- Merge to development branch

---

## Appendices

### Appendix A: Expected Audio Properties

**Diga Output Format**:
- Sample Rate: 24000 Hz (24 kHz)
- Channels: 1 (mono)
- Bit Depth: 16-bit (PCM)
- Codec: Linear PCM
- Container: WAV, AIFF, or M4A

### Appendix B: File Size Estimates

**Minimum Sizes**:
- WAV header: 44 bytes
- AIFF header: ~54 bytes
- M4A header: ~100+ bytes

**Typical Sizes for "Hello world"** (~1 second):
- WAV: ~48KB (24000 samples × 2 bytes + 44 byte header)
- AIFF: ~48KB (similar to WAV)
- M4A: ~10-20KB (compressed)

### Appendix C: Silence Detection Rationale

**Why RMS > 0.01?**
- Pure silence = RMS of 0.0
- Background noise in recording = RMS ~0.001-0.005
- Actual speech = RMS ~0.05-0.2
- Threshold of 0.01 provides comfortable margin

**Why Peak > 0.1?**
- Normalized audio peaks at ±1.0
- Speech typically has peaks > 0.3
- Threshold of 0.1 is very conservative
- Allows for low-volume speech while rejecting silence

### Appendix D: Example Test Output

**Successful Test**:
```
✓ diga generates valid WAV file with audio data (3.24s)
  Binary: ./bin/diga
  Output: /tmp/diga-test-12345678.wav
  File size: 47,844 bytes
  RIFF header: ✓
  WAVE marker: ✓
  Sample rate: 24000 Hz ✓
  Channels: 1 ✓
  Format: PCM Int16 ✓
  Audio analysis: RMS=0.087, Peak=0.654, Frames=23900
  Not silence: ✓
```

**Failed Test (Silence)**:
```
✗ diga generates valid WAV file with audio data
  Audio analysis: RMS=0.003, Peak=0.012, Frames=23900
  ✗ Silence detected: Audio RMS (0.003) is below threshold (0.01)
```

---

## Conclusion

This execution plan provides a comprehensive roadmap for implementing audio generation integration tests. The phased approach allows for incremental development and testing, with clear success criteria at each stage.

Key benefits:
- **Comprehensive validation**: Tests cover file format, audio properties, and signal quality
- **CI-ready**: Designed to run efficiently in CI with model caching
- **Maintainable**: Clear helper functions, good error messages, proper cleanup
- **Extensible**: Easy to add new formats or validation criteria

The tests will provide high confidence that the diga binary produces valid, non-silent audio across all supported formats.
