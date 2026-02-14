# Critical Path Gaps — Audio Generation Test

These 5 gaps MUST be resolved before implementation can begin.

---

## 🔴 Gap 1: Working Directory and Binary Path Resolution

### The Problem
When tests run via `xcodebuild test`, we don't know:
- What is the current working directory?
- Where is the test file located relative to repo root?
- How do we reliably find `./bin/diga`?

### Current Plan Assumption (Unvalidated)
```swift
let binaryPaths = [
    "./bin/diga",              // Assumes CWD = repo root
    "./.build/debug/diga",     // WRONG - xcodebuild uses DerivedData
    "./.build/release/diga"    // WRONG - xcodebuild uses DerivedData
]
```

### Why This Matters
If we can't find the binary, **every test fails immediately**.

### Questions to Answer
- **Q1**: What is `FileManager.default.currentDirectoryPath` when running `xcodebuild test`?
- **Q2**: Can we use `#filePath` (e.g., `Tests/DigaTests/File.swift`) to navigate to repo root?
- **Q3**: Should we use an environment variable passed from `xcodebuild`?
- **Q4**: Should we search multiple locations or fail fast?

### Proposed Resolution Strategy

**Option A: Use #filePath to find repo root** (Recommended)
```swift
// In test file: Tests/DigaTests/DigaBinaryIntegrationTests.swift
func findBinaryPath() -> String? {
    // #filePath = ".../SwiftVoxAlta/Tests/DigaTests/DigaBinaryIntegrationTests.swift"
    let testFilePath = #filePath
    let testFileURL = URL(fileURLWithPath: testFilePath)

    // Navigate up: Tests/DigaTests -> Tests -> SwiftVoxAlta (repo root)
    let repoRoot = testFileURL
        .deletingLastPathComponent()  // Remove file
        .deletingLastPathComponent()  // Remove DigaTests
        .deletingLastPathComponent()  // Remove Tests

    let binaryPath = repoRoot
        .appendingPathComponent("bin")
        .appendingPathComponent("diga")
        .path

    guard FileManager.default.fileExists(atPath: binaryPath) else {
        return nil
    }

    return binaryPath
}
```

**Option B: Use environment variable**
```swift
func findBinaryPath() -> String? {
    if let projectDir = ProcessInfo.processInfo.environment["PROJECT_DIR"] {
        let binaryPath = "\(projectDir)/bin/diga"
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            return nil
        }
        return binaryPath
    }
    return nil
}

// Then pass in xcodebuild:
// xcodebuild test -scheme SwiftVoxAlta-Package \
//   PROJECT_DIR="$(pwd)" \
//   -destination 'platform=macOS'
```

**Option C: Search multiple locations**
```swift
func findBinaryPath() -> String? {
    let searchPaths = [
        "./bin/diga",                                    // If CWD is repo root
        "../../../bin/diga",                             // Relative from test file
        "\(NSHomeDirectory())/Projects/SwiftVoxAlta/bin/diga"  // Absolute (brittle)
    ]

    return searchPaths.first { FileManager.default.fileExists(atPath: $0) }
}
```

### Action Required
**Run empirical test** to determine actual working directory:

```bash
# Add this test temporarily:
cat > Tests/DigaTests/WorkingDirectoryTest.swift << 'EOF'
import Foundation
import Testing

@Suite("Working Directory Detection")
struct WorkingDirectoryTests {
    @Test("Detect working directory during xcodebuild test")
    func detectWorkingDirectory() {
        let cwd = FileManager.default.currentDirectoryPath
        let filePath = #filePath

        print("========================================")
        print("Current Working Directory: \(cwd)")
        print("Test File Path: \(filePath)")
        print("./bin/diga exists: \(FileManager.default.fileExists(atPath: "./bin/diga"))")
        print("../../../bin/diga exists: \(FileManager.default.fileExists(atPath: "../../../bin/diga"))")
        print("========================================")

        // This test always passes - just for observation
        #expect(true)
    }
}
EOF

# Run the test:
xcodebuild test \
  -scheme SwiftVoxAlta-Package \
  -destination 'platform=macOS' \
  -only-testing:DigaTests/WorkingDirectoryTests 2>&1 | grep "========"

# Clean up:
rm Tests/DigaTests/WorkingDirectoryTest.swift
```

### Decision Needed
**Choose Option A, B, or C** based on empirical test results.

---

## 🔴 Gap 2: Model Download on First Run

### The Problem
First test run requires downloading 2.4GB model:
- Download can take 5-30 minutes depending on connection
- Tests will hang/timeout if not handled properly
- CI cache may be empty on first PR from new contributor

### Current Plan Assumption (Unvalidated)
- "Add timeout of 300 seconds for first run"
- But: 300s might not be enough for slow connections
- No strategy for what happens if download fails

### Why This Matters
**Tests will fail or timeout** on first run without proper handling.

### Questions to Answer
- **Q5**: Should tests skip if model not cached?
- **Q6**: Should tests have a longer timeout for first run?
- **Q7**: What if model download fails? Retry? Fail test? Skip?
- **Q8**: How do we detect if model is cached vs needs download?

### Proposed Resolution Strategy

**Option A: Skip tests if model not cached** (Recommended for MVP)
```swift
func isModelCached(modelId: String) -> Bool {
    let acervoCache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/SharedModels")
        .appendingPathComponent(modelId)

    return FileManager.default.fileExists(atPath: acervoCache.path)
}

@Suite("Binary Audio Generation Integration Tests")
struct DigaBinaryIntegrationTests {

    @Test("WAV generation",
          .enabled(if: isModelCached("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")))
    func wavGeneration() async throws {
        // Test only runs if model is cached
        ...
    }
}
```

**Option B: Download model in test setup** (Complex)
```swift
@Suite("Binary Audio Generation Integration Tests")
struct DigaBinaryIntegrationTests {

    init() async throws {
        // Download model if not cached
        if !isModelCached("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16") {
            print("Downloading model (this may take 5-30 minutes)...")
            // Run diga once to trigger download
            let result = try await runDiga(
                args: ["--model", "0.6b", "-o", "/tmp/warmup.wav", "test"],
                timeout: 1800  // 30 minute timeout
            )
            // Clean up
            try? FileManager.default.removeItem(atPath: "/tmp/warmup.wav")
        }
    }
}
```

**Option C: Fail with clear message if model not cached**
```swift
@Test("WAV generation")
func wavGeneration() async throws {
    guard isModelCached("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16") else {
        Issue.record(
            "Model not cached. Run this first to download:\n" +
            "./bin/diga --model 0.6b -o /tmp/test.wav 'test'"
        )
        return
    }

    // Proceed with test...
}
```

### CI Consideration
CI already has model caching configured:
```yaml
- name: Cache TTS models
  uses: actions/cache@v4
  with:
    path: |
      ~/Library/SharedModels
      ~/Library/Caches/intrusive-memory/Models
    key: tts-models-v1
```

So in CI, model should be cached after first successful run.

### Action Required
**Decide on strategy:**
1. Should local developers be expected to manually download model first?
2. Should tests auto-download (complex, long timeout)?
3. Should tests skip gracefully (simple, explicit)?

### Decision Needed
**Choose Option A, B, or C** and document in developer README.

---

## 🔴 Gap 3: Test Framework Integration (Async/Await)

### The Problem
Plan shows synchronous code but doesn't specify async/await usage:
- Process spawning blocks thread (should it be async?)
- AVFoundation file I/O blocks thread (should it be async?)
- Swift Testing prefers async test functions

### Current Plan Code (Ambiguous)
```swift
// Is this sync or async?
private func runDiga(args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

// Is this sync or async?
@Test("diga generates valid WAV file")
func wavGeneration() throws {
    let result = try runDiga(args: [...])
    ...
}
```

### Why This Matters
- Incorrect concurrency can cause tests to block or fail
- Swift 6 strict concurrency will flag issues
- Test performance affected by blocking vs async I/O

### Questions to Answer
- **Q9**: Should test functions be `async throws` or just `throws`?
- **Q10**: Should `runDiga()` be async or sync? (Process.run() is synchronous)
- **Q11**: Should file I/O be wrapped in async contexts?
- **Q12**: Do we need `@MainActor` annotations for file operations?

### Proposed Resolution Strategy

**Option A: Keep sync (simpler, blocks thread)**
```swift
private func runDiga(args: [String], timeout: TimeInterval = 30) throws -> ProcessResult {
    let process = Process()
    // ... setup process ...

    try process.run()

    // Manual timeout handling
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }

    if process.isRunning {
        process.terminate()
        throw TestError.timeout
    }

    return ProcessResult(exitCode: process.terminationStatus, ...)
}

@Test("WAV generation")
func wavGeneration() throws {  // Sync
    let result = try runDiga(args: ["--model", "0.6b", "-o", "/tmp/test.wav", "test"])
    #expect(result.exitCode == 0)
}
```

**Option B: Make async (cleaner, non-blocking)** (Recommended)
```swift
private func runDiga(args: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
    let process = Process()
    // ... setup process ...

    try process.run()

    // Async timeout handling
    return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
        group.addTask {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: ...,
                        stderr: ...
                    ))
                }
            }
        }

        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw TestError.timeout
        }

        return try await group.next()!
    }
}

@Test("WAV generation")
func wavGeneration() async throws {  // Async
    let result = try await runDiga(args: ["--model", "0.6b", "-o", "/tmp/test.wav", "test"])
    #expect(result.exitCode == 0)
}
```

**Option C: Hybrid (sync wrapper over async)**
```swift
// Provide both for flexibility
private func runDigaSync(args: [String]) throws -> ProcessResult {
    // For simple cases
}

private func runDigaAsync(args: [String]) async throws -> ProcessResult {
    // For complex cases with proper timeout
}
```

### Swift Testing Best Practices
From Swift Testing documentation:
- ✅ Prefer `async throws` for I/O operations
- ✅ Use `await` for potentially blocking operations
- ✅ Swift Testing handles async contexts automatically

### Action Required
**Validate async syntax** with minimal test:

```bash
# Add temporary test:
cat > Tests/DigaTests/AsyncValidationTest.swift << 'EOF'
import Foundation
import Testing

@Suite("Async Validation")
struct AsyncValidationTests {

    @Test("Async process spawning works")
    func asyncProcessTest() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["hello"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()

        // Async wait
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(output == "hello")
    }
}
EOF

# Run test:
xcodebuild test \
  -scheme SwiftVoxAlta-Package \
  -destination 'platform=macOS' \
  -only-testing:DigaTests/AsyncValidationTests

# Clean up:
rm Tests/DigaTests/AsyncValidationTest.swift
```

### Decision Needed
**Choose Option A or B** (recommend B for modern Swift practices).

---

## 🔴 Gap 4: Threshold Validation (RMS/Peak Values)

### The Problem
Plan proposes thresholds with **zero empirical validation**:
- RMS > 0.01 (guess)
- Peak > 0.1 (guess)

These could be too strict (false negatives) or too loose (false positives).

### Current Plan Assumption (Unvalidated)
```swift
// From plan:
guard rms > 0.01 else {
    throw TestError.silenceDetected("Audio RMS (\(rms)) is below threshold (0.01)")
}

guard peakAmplitude > 0.1 else {
    throw TestError.silenceDetected("Audio peak amplitude (\(peakAmplitude)) is too low")
}
```

### Why This Matters
**Wrong thresholds = flaky tests**:
- Too strict → Real audio fails test (false negative)
- Too loose → Silence passes test (false positive)

### Questions to Answer
- **Q13**: What is the actual RMS level of diga output?
- **Q14**: What is the actual peak amplitude of diga output?
- **Q15**: Do values vary significantly by voice, model, or text?
- **Q16**: Should we have different thresholds per format (WAV vs M4A)?

### Proposed Resolution Strategy

**Step 1: Measure actual diga output**
```bash
# Generate test audio
./bin/diga --model 0.6b -o /tmp/test.wav "The quick brown fox jumps over the lazy dog."

# Analyze with ffprobe
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels -of json /tmp/test.wav

# Analyze RMS/peak with ffmpeg
ffmpeg -i /tmp/test.wav -af "volumedetect,astats" -f null - 2>&1 | grep -E "mean_volume|max_volume|RMS"

# Expected output (example):
# [Parsed_volumedetect_0] mean_volume: -18.2 dB
# [Parsed_volumedetect_0] max_volume: -3.5 dB
# [Parsed_astats_1] RMS level dB: -15.3

# Convert dB to linear:
# -18.2 dB = 10^(-18.2/20) = 0.123 (RMS)
# -3.5 dB = 10^(-3.5/20) = 0.668 (Peak)
```

**Step 2: Test with Swift AVFoundation**
```swift
// Temporary validation script
import AVFoundation
import Foundation

let url = URL(fileURLWithPath: "/tmp/test.wav")
let audioFile = try AVAudioFile(forReading: url)
let format = audioFile.processingFormat
let frameCount = AVAudioFrameCount(audioFile.length)

let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
try audioFile.read(into: buffer)

let floatData = buffer.floatChannelData![0]
var sumSquares: Float = 0.0
var peak: Float = 0.0

for i in 0..<Int(buffer.frameLength) {
    let sample = floatData[i]
    sumSquares += sample * sample
    peak = max(peak, abs(sample))
}

let rms = sqrt(sumSquares / Float(buffer.frameLength))

print("RMS: \(rms)")
print("Peak: \(peak)")
print("Suggested RMS threshold: \(rms * 0.1)")  // 10% of actual
print("Suggested Peak threshold: \(peak * 0.1)")  // 10% of actual
```

**Step 3: Set conservative thresholds**
Based on empirical data, set thresholds to 10% of actual values:
```swift
// If actual RMS = 0.123, threshold = 0.0123
// If actual Peak = 0.668, threshold = 0.0668

let rmsThreshold: Float = 0.01  // Update after measurement
let peakThreshold: Float = 0.05  // Update after measurement
```

### Action Required
1. **Generate audio with diga**
2. **Measure actual RMS/Peak values**
3. **Update plan with empirical thresholds**
4. **Document measurement methodology**

### Decision Needed
**Run measurement** and update plan with actual values (not guesses).

---

## 🔴 Gap 5: Binary Build Dependency

### The Problem
`make test` does NOT build the binary:
```makefile
# Current Makefile:
test:
	xcodebuild test -scheme $(TEST_SCHEME) -destination 'platform=macOS'
```

So if developer runs `make test` without `make install` first:
```bash
# This will fail:
make clean  # Removes bin/diga
make test   # Tests try to find bin/diga → not found → all tests fail
```

### Current Plan Assumption (Unvalidated)
Plan assumes binary exists but doesn't specify how to ensure it.

### Why This Matters
**Developer experience**:
- Confusing: "Why are tests failing?"
- Non-obvious: "Oh, I need to run `make install` first"
- Error-prone: Easy to forget

### Questions to Answer
- **Q17**: Should `make test` automatically build the binary?
- **Q18**: Should tests skip gracefully if binary not found?
- **Q19**: Should we have separate `make test-unit` vs `make test-integration`?
- **Q20**: What should CI do? (Currently has separate `build` and `integration-tests` jobs)

### Proposed Resolution Strategy

**Option A: Make `test` depend on `install`** (Simple, explicit)
```makefile
# Update Makefile:
test: install
	xcodebuild test -scheme $(TEST_SCHEME) -destination 'platform=macOS'
```

**Pros**: Always works, no surprises
**Cons**: Slower (rebuilds binary every time), may not match developer intent

---

**Option B: Separate test targets** (Flexible)
```makefile
# Unit tests only (no binary needed)
test-unit:
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' \
	  -skip-testing:DigaTests/DigaBinaryIntegrationTests

# Integration tests (requires binary)
test-integration: install
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' \
	  -only-testing:DigaTests/DigaBinaryIntegrationTests

# All tests
test: test-unit test-integration
```

**Pros**: Flexible, fast unit tests, explicit integration tests
**Cons**: More complex, developers need to know which to run

---

**Option C: Skip tests if binary not found** (Graceful degradation)
```swift
@Suite("Binary Audio Generation Integration Tests")
struct DigaBinaryIntegrationTests {

    static var binaryPath: String? = {
        // Try to find binary
        return findBinaryPath()
    }()

    @Test("WAV generation", .enabled(if: binaryPath != nil))
    func wavGeneration() async throws {
        let binary = Self.binaryPath!
        // Run test...
    }
}
```

```makefile
# Makefile unchanged:
test:
	xcodebuild test -scheme $(TEST_SCHEME) -destination 'platform=macOS'
	@echo "Note: Binary integration tests skipped (run 'make install' first)"
```

**Pros**: Simple, flexible, never fails unexpectedly
**Cons**: Tests might silently skip, easy to miss

---

### CI Consideration
Current CI structure:
```yaml
jobs:
  build:
    - name: Build all targets

  integration-tests:
    needs: build
    - name: Build release binary
    - name: Verify diga binary exists
```

CI explicitly builds binary in integration job, so this is only a local dev issue.

### Action Required
**Decide on developer workflow:**
1. Should developers always run `make install && make test`?
2. Should `make test` be smart enough to build binary if needed?
3. Should we have separate targets for unit vs integration tests?

### Decision Needed
**Choose Option A, B, or C** and update Makefile + README accordingly.

---

## Summary: Decisions Needed

| Gap | Decision Required | Blocking? |
|-----|-------------------|-----------|
| **Gap 1: Binary Path** | Choose Option A/B/C, run empirical test | 🔴 YES |
| **Gap 2: Model Download** | Choose Option A/B/C, document strategy | 🔴 YES |
| **Gap 3: Async/Await** | Choose Option A/B, validate syntax | 🔴 YES |
| **Gap 4: Thresholds** | Run measurement, update values | 🔴 YES |
| **Gap 5: Build Dependency** | Choose Option A/B/C, update Makefile | 🟡 MEDIUM |

## Next Steps

### Immediate (Can do now)
1. ✅ Run **Gap 1** empirical test (working directory detection)
2. ✅ Run **Gap 3** validation (async syntax test)
3. ✅ Run **Gap 4** measurement (RMS/Peak analysis)

### Requires Discussion (You + me)
4. ⚪ Decide **Gap 2** strategy (model download handling)
5. ⚪ Decide **Gap 5** approach (build dependency)

### After Decisions
6. Update execution plan with confirmed values
7. Hand off to `/sprint-supervisor`

---

**Which gap should we tackle first?** I recommend Gap 1 (working directory) since it's quick to test and blocks everything else.
