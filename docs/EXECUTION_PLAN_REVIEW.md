# Audio Generation Test Execution Plan — Completeness Review

## Executive Summary

**Overall Assessment**: The execution plan is **80% complete** but has **critical gaps** that must be resolved before implementation.

**Key Findings**:
- ✅ Clear technical approach with detailed code examples
- ✅ Good phase breakdown and risk mitigation
- ❌ Missing critical path resolution details
- ❌ Unclear test framework integration points
- ❌ Unvalidated threshold assumptions
- ❌ Incomplete first-run/model download handling

---

## 1. Point A: Current State (Where We Are)

### ✅ What We Know

**Test Infrastructure**:
- 22 test files, 361 test cases (using Swift Testing framework, NOT XCTest)
- `Tests/DigaTests/DigaCLIIntegrationTests.swift` exists with 24 CLI flag tests
- `Tests/SwiftVoxAltaTests/IntegrationTests.swift` exists with VoiceProvider pipeline tests
- All tests use `import Testing` and `@Test` / `@Suite` attributes

**Build System**:
- Binary builds to `./bin/diga` via `make install` (debug) or `make release` (release)
- Binary lives in DerivedData, copied to `./bin/` by Makefile
- Metal bundle (`mlx-swift_Cmlx.bundle`) must be copied alongside binary
- Tests run via `xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS'`

**CI Environment**:
- `.github/workflows/tests.yml` has existing `audio-integration` job (lines 58-131)
- CI already does bash-based audio validation:
  - Synthesizes test audio: `./bin/diga --model 0.6b -o /tmp/test.wav "Hello from CI"`
  - Validates file size > 44 bytes
  - Validates RIFF/WAVE headers with `xxd`
  - Validates PCM data is not all zeros
  - Uploads audio artifact on failure
- Model caching configured: `~/Library/SharedModels` and `~/Library/Caches/intrusive-memory/Models`

**Audio Infrastructure**:
- `AudioFileWriter.swift` handles WAV/AIFF/M4A conversion
- WAV output format: 16-bit PCM, 24kHz, mono
- Existing audio format tests in `DigaAudioFileWriterTests.swift` (19 test cases)

### ❌ What We DON'T Know

**Critical Unknowns**:
1. **Test working directory**: When tests run via `xcodebuild test`, what is `FileManager.default.currentDirectoryPath`? Is it repo root?
2. **Binary availability during tests**: Is `./bin/diga` available when running `make test`, or only after `make install`/`make release`?
3. **Model download time**: How long does first model download take in practice? (Plan assumes but doesn't measure)
4. **Actual RMS values**: What RMS/peak values does diga output produce? (Thresholds are guesses)
5. **M4A validation quirks**: Does AVAudioFile handle M4A files correctly on all macOS versions?
6. **Test parallelism**: Can multiple tests load models simultaneously without conflicts?

---

## 2. Point B: Desired End State (Where We're Going)

### ✅ Clearly Defined Goals

**Functional Requirements** (from user):
- ✅ Generate audio file using the binary
- ✅ Verify non-zero length
- ✅ Verify binary audio data exists in file
- ✅ Verify type matches extension
- ✅ Verify audio is not silence

**Plan Deliverables**:
- Swift-based integration tests in `DigaCLIIntegrationTests.swift`
- Tests complement (not replace) existing bash CI validation
- Deep validation using AVFoundation
- Multi-format support (WAV, AIFF, M4A)
- Clear error messages and proper cleanup

### ❌ Unclear Goals

**Missing Specifications**:
1. **Performance targets**: "< 30 seconds" mentioned but not validated. Is this per test or per suite?
2. **Coverage targets**: How many test cases? Plan suggests 5-6 but doesn't lock this down
3. **Integration strategy**: Should these tests:
   - Run on every `make test`? (Would require binary pre-built)
   - Run only in CI? (Current bash tests run in CI only)
   - Run as separate `make test-integration` target?
4. **Failure impact**: Should CI fail if audio quality is poor (low RMS) or only if completely silent?
5. **Test data**: What text phrases to use? "Hello world" mentioned but not standardized

---

## 3. Critical Gaps (Must Resolve Before Implementation)

### 🔴 Gap 1: Working Directory and Binary Path Resolution

**Problem**: Test working directory during `xcodebuild test` is unknown.

**Impact**: Binary path resolution will fail if not repo root.

**Evidence**:
```swift
// From plan:
let binaryPaths = [
    "./bin/diga",              // Assumes CWD = repo root
    "./.build/debug/diga",     // Wrong - xcodebuild doesn't use .build
    "./.build/release/diga"    // Wrong - xcodebuild doesn't use .build
]
```

**Questions**:
- Q1: What is `FileManager.default.currentDirectoryPath` when running `xcodebuild test`?
- Q2: Can we use `#filePath` to get repo root from test file location?
- Q3: Should we use environment variable `PROJECT_DIR` or similar?

**Recommendation**: Add Phase 0 to validate working directory and binary location.

---

### 🔴 Gap 2: Model Download on First Run

**Problem**: Plan mentions "timeout of 300 seconds" but doesn't specify behavior when model is not cached.

**Impact**: Tests will fail or hang on first run in clean CI environment.

**Current CI Behavior**:
- Model cache configured but may be empty on first PR from new contributor
- No timeout handling in bash tests (relies on cache)

**Questions**:
- Q3: Should test skip if model not cached? (Use `.tags(.requiresModel)` or similar?)
- Q4: Should test have conditional behavior for first vs subsequent runs?
- Q5: What if model download fails? Retry? Fail test?

**Recommendation**: Add explicit first-run handling strategy to plan.

---

### 🔴 Gap 3: Test Framework Integration

**Problem**: Plan uses generic Swift syntax but doesn't match Swift Testing framework specifics.

**Impact**: Code examples won't compile as-written.

**Issues**:
```swift
// Plan shows:
#expect(throws: AudioFileWriterError.self) {
    try AudioFileWriter.write(...)
}

// But Swift Testing uses:
#expect(throws: AudioFileWriterError.self) {
    try AudioFileWriter.write(...)
}
// ✅ This is actually correct for Swift Testing

// However, plan shows:
func runDiga(args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

// Should be async:
func runDiga(args: [String]) async throws -> (exitCode: Int32, stdout: String, stderr: String)
```

**Questions**:
- Q6: Should helper functions be async? (Process.run() is synchronous but blocks)
- Q7: Should test functions be async? (Common pattern: `@Test func testName() async throws`)
- Q8: Do we need `@MainActor` annotations for file I/O?

**Recommendation**: Update all code examples to use async/await and Swift Testing syntax.

---

### 🔴 Gap 4: Threshold Validation

**Problem**: RMS > 0.01 and Peak > 0.1 are **guesses** not validated against actual diga output.

**Impact**: Tests may have false positives (silence passes) or false negatives (audio fails).

**Current Evidence**: None. No empirical data on diga output levels.

**Questions**:
- Q9: What are actual RMS/Peak values for diga output?
- Q10: Do values vary significantly by voice or text content?
- Q11: Should thresholds be configurable or hard-coded?

**Recommendation**: Add Phase 0 task to empirically measure diga output and validate thresholds.

---

### 🔴 Gap 5: Binary Build Dependency

**Problem**: Tests assume binary is pre-built but `make test` doesn't build binary.

**Impact**: `make test` will fail with "binary not found" unless user runs `make install` first.

**Current Behavior**:
```makefile
# make test does NOT build binary
test:
	xcodebuild test -scheme $(TEST_SCHEME) -destination 'platform=macOS'
```

**Questions**:
- Q12: Should `make test` depend on `make install`?
- Q13: Should tests skip if binary not found (graceful degradation)?
- Q14: Should tests build binary on demand?

**Recommendation**: Decide on test invocation strategy and update Makefile if needed.

---

## 4. Important Open Questions

### Testing Strategy

**Q15: Test organization** - Should these tests:
- Option A: Live in `DigaCLIIntegrationTests.swift` with existing CLI tests (plan's choice)
- Option B: Live in new `DigaBinaryIntegrationTests.swift` for clear separation
- Option C: Live in `IntegrationTests.swift` alongside VoiceProvider tests

**Recommendation**: Option B (new file) for better organization and isolation.

---

**Q16: CI integration** - Should these tests:
- Option A: Supplement existing bash tests (belt-and-suspenders)
- Option B: Replace existing bash tests (DRY principle)
- Option C: Run only locally, bash tests only in CI

**Recommendation**: Option A initially, then Option B after validation period.

---

**Q17: Test data standardization** - What text should we use?
- Option A: Fixed phrase: "The quick brown fox jumps over the lazy dog." (pangram, ~1.5s audio)
- Option B: Multiple phrases for variety
- Option C: Random generated text

**Recommendation**: Option A for reproducibility and consistent audio duration.

---

### Technical Details

**Q18: AVFoundation format handling** - How do we handle M4A quirks?
- M4A is AAC-compressed, AVAudioFile may report different format than WAV/AIFF
- Should we accept `.pcmFormatFloat32` for M4A or require exact match?

**Recommendation**: Accept multiple PCM formats, focus on sample rate and channel count.

---

**Q19: Parallel test execution** - Can tests run concurrently?
- Model loading may not be thread-safe
- File I/O to same model cache directory could conflict

**Recommendation**: Add `.serialized` tag to test suite to force sequential execution.

---

**Q20: Cleanup on test crash** - What if test crashes mid-execution?
- Temp files may not be cleaned up by `defer`
- Model may be left in corrupted state

**Recommendation**: Use dedicated temp directory per test run: `/tmp/diga-test-{UUID}/`

---

## 5. Missing Implementation Details

### Code Examples Need Updating

**Issue 1: Process spawning error handling**

Plan shows:
```swift
try process.run()
process.waitUntilExit()
```

Should be:
```swift
do {
    try process.run()
} catch {
    throw TestError.processError("Failed to spawn diga: \(error)")
}

// Add timeout:
let timeoutSeconds: TimeInterval = 30
var isTimedOut = false
DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
    if process.isRunning {
        isTimedOut = true
        process.terminate()
    }
}
process.waitUntilExit()

if isTimedOut {
    throw TestError.processError("Process timed out after \(timeoutSeconds)s")
}
```

---

**Issue 2: AVFoundation imports missing**

Plan doesn't specify imports needed:
```swift
import AVFoundation  // Missing in plan
import Foundation
import Testing
@testable import diga
```

---

**Issue 3: Temp file path generation**

Plan uses:
```swift
let outputPath = tempDir.appendingPathComponent("test.wav").path
```

Should be more robust:
```swift
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tempDir)
}

let outputPath = tempDir.appendingPathComponent("output.wav").path
```

---

### Missing Test Cases

Plan mentions 5 test cases but actual needs may include:

**Additional Test Cases**:
1. ✅ Basic WAV generation (planned)
2. ✅ AIFF format (planned)
3. ✅ M4A format (planned)
4. ✅ Silence detection (planned)
5. ✅ Binary not found (planned)
6. ❌ **Long text handling** (what if text > 500 words?)
7. ❌ **Special characters in text** (emoji, unicode, quotes)
8. ❌ **Binary version mismatch** (old binary, new tests)
9. ❌ **Concurrent execution** (two tests run simultaneously)
10. ❌ **Disk full scenario** (write to full filesystem)

**Recommendation**: Add cases 6-7 to MVP scope, cases 8-10 to backlog.

---

## 6. Phase 0: Pre-Implementation Tasks

Before starting Phase 1, we need:

### Task 1: Empirical Baseline Measurement

**Goal**: Measure actual diga output to validate assumptions

**Steps**:
1. Run `./bin/diga --model 0.6b -o /tmp/test.wav "The quick brown fox jumps over the lazy dog."`
2. Analyze output with `ffprobe` or AVFoundation
3. Record:
   - Actual RMS level
   - Actual peak amplitude
   - Audio duration
   - File size
4. Validate thresholds (RMS > 0.01, Peak > 0.1)
5. Update plan with empirical values

**Success Criteria**: Thresholds validated or adjusted based on data.

---

### Task 2: Working Directory Detection

**Goal**: Determine test working directory and binary path resolution strategy

**Steps**:
1. Create minimal test in `DigaCLIIntegrationTests.swift`:
   ```swift
   @Test("Detect working directory")
   func detectWorkingDirectory() {
       let cwd = FileManager.default.currentDirectoryPath
       print("Working directory: \(cwd)")
       print("File path: \(#filePath)")

       let binExists = FileManager.default.fileExists(atPath: "./bin/diga")
       print("./bin/diga exists: \(binExists)")
   }
   ```
2. Run via `xcodebuild test`
3. Record results
4. Update plan with correct path resolution strategy

**Success Criteria**: Binary path resolution method determined.

---

### Task 3: Model Download Time Measurement

**Goal**: Measure actual model download time to set realistic timeouts

**Steps**:
1. Clear model cache: `rm -rf ~/Library/SharedModels ~/Library/Caches/intrusive-memory`
2. Time cold run: `time ./bin/diga --model 0.6b -o /tmp/test.wav "test"`
3. Time warm run: `time ./bin/diga --model 0.6b -o /tmp/test.wav "test"`
4. Record download time and inference time separately
5. Set timeout to `max(download_time * 2, 300s)`

**Success Criteria**: Timeout value backed by empirical data.

---

### Task 4: Test Framework Integration Validation

**Goal**: Validate Swift Testing syntax and async/await usage

**Steps**:
1. Create minimal async test:
   ```swift
   @Test("Async process spawning")
   func asyncProcessTest() async throws {
       let process = Process()
       process.executableURL = URL(fileURLWithPath: "/bin/echo")
       process.arguments = ["hello"]
       try process.run()
       process.waitUntilExit()
       #expect(process.terminationStatus == 0)
   }
   ```
2. Verify compilation and execution
3. Update plan with confirmed syntax

**Success Criteria**: Test compiles and runs successfully.

---

### Task 5: Build Dependency Resolution

**Goal**: Decide on test invocation strategy and update Makefile if needed

**Options**:
- Option A: Update `Makefile` so `make test` depends on `make install`
  ```makefile
  test: install
  	xcodebuild test -scheme $(TEST_SCHEME) -destination 'platform=macOS'
  ```
- Option B: Tests skip gracefully if binary not found:
  ```swift
  @Test("WAV generation", .enabled(if: binaryExists()))
  func wavGeneration() async throws { ... }
  ```
- Option C: Tests build binary on first invocation (complex, not recommended)

**Recommendation**: Option A (simple, explicit) or Option B (flexible).

---

## 7. Updated Implementation Phases

After completing Phase 0 tasks, proceed with:

### Phase 1: Minimal Viable Test (1 day)

**Scope**: Single WAV test that proves end-to-end flow

**Deliverables**:
- Helper: `runDiga()` with timeout
- Helper: `validateFileExists()`
- Test: "diga generates valid WAV file"
  - File exists
  - Size > 44 bytes
  - Process exits 0

**Success Criteria**: Test passes locally and in CI

---

### Phase 2: Format Validation (1 day)

**Scope**: Add header and AVFoundation validation

**Deliverables**:
- Helper: `validateAudioHeaders()` (WAV only)
- Helper: `validateAudioFormat()` (AVFoundation)
- Update Phase 1 test with full validation

**Success Criteria**: Test validates audio format correctly

---

### Phase 3: Silence Detection (1 day)

**Scope**: Add RMS/peak analysis

**Deliverables**:
- Helper: `validateNotSilence()` with empirical thresholds
- Negative test: "Detects silence correctly"

**Success Criteria**: Both positive and negative tests pass

---

### Phase 4: Multi-Format (1 day)

**Scope**: AIFF and M4A support

**Deliverables**:
- Update `validateAudioHeaders()` for AIFF/M4A
- Test: "AIFF generation"
- Test: "M4A generation"

**Success Criteria**: All 3 formats work

---

### Phase 5: Error Handling (0.5 days)

**Scope**: Negative tests and edge cases

**Deliverables**:
- Test: "Binary not found"
- Test: "Invalid arguments"
- Timeout handling in `runDiga()`

**Success Criteria**: All error cases handled

---

### Phase 6: CI Integration (0.5 days)

**Scope**: Verify CI execution and polish

**Deliverables**:
- CI passes with tests enabled
- Artifacts uploaded on failure
- Documentation updated

**Success Criteria**: Green CI build

---

## 8. Risk Assessment

### Critical Risks (Must Mitigate)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Working directory mismatch | High | High | Complete Phase 0 Task 2 |
| Model download timeout | Medium | High | Complete Phase 0 Task 3 |
| False negative (audio fails test) | Medium | High | Complete Phase 0 Task 1 |
| Binary not built during test | Medium | High | Complete Phase 0 Task 5 |

### Medium Risks (Should Mitigate)

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| M4A format quirks | Low | Medium | Test thoroughly, accept format variants |
| Parallel execution conflicts | Low | Medium | Use `.serialized` tag on suite |
| Temp file cleanup failure | Low | Low | Use unique temp dirs per test |

---

## 9. Recommendations

### Critical Path (Must Do)

1. ✅ **Complete Phase 0 tasks** before any implementation
2. ✅ **Validate all assumptions** with empirical data
3. ✅ **Update plan** with confirmed working directory and binary paths
4. ✅ **Choose test file location** (recommend new file: `DigaBinaryIntegrationTests.swift`)
5. ✅ **Decide build dependency strategy** (recommend: `make test` depends on `make install`)

### Important Improvements (Should Do)

1. ✅ Add async/await to all code examples
2. ✅ Standardize test data (use pangram)
3. ✅ Add `.serialized` tag to prevent parallel conflicts
4. ✅ Document imports clearly at top of each code block
5. ✅ Add test case for long text and special characters

### Nice to Have (Could Do)

1. ⚪ Add performance benchmarking to tests
2. ⚪ Add audio quality metrics (SNR, THD)
3. ⚪ Add test for voice selection (`-v` flag)
4. ⚪ Add test for model selection (`--model` flag)

---

## 10. Proposed Plan Updates

### Add New Section: "Phase 0: Pre-Implementation Validation"

Insert before current Phase 1, containing all 5 tasks from Section 6 above.

### Update Section: "Implementation Details"

1. Change all helpers to async:
   ```swift
   func runDiga(args: [String]) async throws -> (exitCode: Int32, stdout: String, stderr: String)
   ```

2. Add proper imports to all code examples:
   ```swift
   import AVFoundation
   import Foundation
   import Testing
   @testable import diga
   ```

3. Update binary paths to use confirmed working directory strategy (TBD after Phase 0 Task 2)

4. Update thresholds to empirical values (TBD after Phase 0 Task 1)

### Update Section: "Test Structure"

Change location from `DigaCLIIntegrationTests.swift` to new file:
```
Location: Tests/DigaTests/DigaBinaryIntegrationTests.swift
Suite: @Suite("Binary Audio Generation Integration Tests", .serialized)
```

---

## 11. Open Questions Summary

**Must Answer Before Implementation** (Phase 0):
- Q1: What is test working directory?
- Q2: How to resolve binary path from tests?
- Q3: Should test skip if model not cached?
- Q9: What are actual RMS/Peak values?
- Q12: Should `make test` build binary?

**Should Answer During Implementation**:
- Q15: Which test file to use?
- Q16: Supplement or replace bash tests?
- Q17: What test data to use?

**Can Answer Later**:
- Q18: M4A format handling details
- Q19: Parallel execution strategy
- Q20: Crash cleanup strategy

---

## 12. Conclusion

**The execution plan is solid but incomplete**. Before implementation can begin, we must:

1. **Complete Phase 0 tasks** to validate assumptions
2. **Update plan** with empirical data
3. **Resolve critical path questions**

**Estimated Timeline**:
- Phase 0: 1 day (validation and measurement)
- Plan updates: 0.5 days (incorporate findings)
- Implementation: 4 days (Phases 1-6)
- **Total: 5.5 days**

**Recommendation**: Do NOT hand this to `/sprint-supervisor` yet. Complete Phase 0 first, then update plan with confirmed values.

---

## 13. Next Steps

### Immediate Actions (Today)

1. Run Phase 0 Task 1 (empirical measurement) ← **Start here**
2. Run Phase 0 Task 2 (working directory detection)
3. Discuss answers to Q12, Q15, Q16, Q17 with user

### Tomorrow

4. Run Phase 0 Task 3 (model download timing)
5. Run Phase 0 Task 4 (test framework validation)
6. Update execution plan with findings
7. Get user approval on updated plan

### Day 3+

8. Begin implementation (Phases 1-6)
9. Hand polished plan to `/sprint-supervisor`

**Do you want me to run Phase 0 tasks now to get empirical data?**
