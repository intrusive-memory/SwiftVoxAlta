# Sprint Handoff: Audio Generation Integration Tests

**Status**: ✅ Ready for Implementation
**Assignee**: `/sprint-supervisor`
**Estimated Time**: 4 hours

---

## What to Build

Add Swift integration tests that spawn the `diga` binary and validate audio output.

**Test file**: `Tests/DigaTests/DigaBinaryIntegrationTests.swift` (~350 lines)

**Test cases** (4):
1. WAV generation - validates all criteria
2. AIFF generation - validates FORM/AIFF headers
3. M4A generation - validates M4A container
4. Binary not found - error handling

**Also update**:
- `Makefile` - add `test-unit` and `test-integration` targets
- `.github/workflows/tests.yml` - separate unit/integration jobs

---

## Key Implementation Details

### 1. Binary Path Resolution (Gap 1 - RESOLVED)

Working directory is `/private/tmp`, NOT repo root. Use `#filePath`:

```swift
private static func findBinaryPath() throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repoRoot = testFileURL
        .deletingLastPathComponent()  // File
        .deletingLastPathComponent()  // DigaTests
        .deletingLastPathComponent()  // Tests
    return repoRoot.appendingPathComponent("bin/diga").path
}
```

### 2. Async Process Spawning (Gap 3 - RESOLVED)

Use `async throws` with timeout:

```swift
private static func runDiga(
    binaryPath: String,
    args: [String],
    timeout: TimeInterval = 30
) async throws -> ProcessResult {
    // Use withThrowingTaskGroup to race process vs timeout
    // See full implementation in FINAL_EXECUTION_PLAN.md
}
```

### 3. Voice Cache Warmup (Gap 2 - RESOLVED)

Auto-generate voices on first run:

```swift
init() async throws {
    guard !Self.areVoicesCached() else { return }

    print("⏳ First run: Generating voice 'alex' (~60 seconds)...")

    let result = try await Self.runDiga(
        binaryPath: binary,
        args: ["-v", "alex", "-o", "/tmp/warmup.wav", "test"],
        timeout: 120
    )

    // Voice now cached at ~/Library/Caches/intrusive-memory/Voices/alex.voice
}
```

### 4. Silence Detection (Gap 4 - RESOLVED)

Empirically validated thresholds:

```swift
let rmsThreshold: Float = 0.02   // 10× below typical speech (0.21-0.42)
let peakThreshold: Float = 0.1   // 3× below typical speech (0.3-0.6)

// Calculate RMS and peak from AVAudioPCMBuffer
// Throw TestError.silenceDetected if below thresholds
```

### 5. Separate Test Targets (Gap 5 - RESOLVED)

**Makefile**:
```makefile
test-unit:
	xcodebuild test -skip-testing:DigaTests/DigaBinaryIntegrationTests

test-integration: install
	xcodebuild test -only-testing:DigaTests/DigaBinaryIntegrationTests

test: test-unit test-integration
```

**CI** (`.github/workflows/tests.yml`):
```yaml
jobs:
  unit-tests:
    runs-on: macos-26
    steps:
      - run: make test-unit

  integration-tests:
    runs-on: macos-26
    steps:
      - uses: actions/cache@v4  # Cache voices
      - run: make test-integration
```

---

## Complete Implementation

See **`docs/FINAL_EXECUTION_PLAN.md`** for:
- Full code for all helpers and tests
- Complete Makefile updates
- Complete CI configuration
- Error handling
- Success criteria

All code is **empirically validated** and ready to copy/paste.

---

## Testing the Implementation

```bash
# After implementation:

# 1. Unit tests (fast, no binary)
make test-unit
# Expected: ✓ 361 tests pass in ~5s

# 2. Integration tests (first run, generates voice)
make test-integration
# Expected:
#   ⏳ Generating voice 'alex' (~60s)
#   ✓ 4 integration tests pass

# 3. Integration tests (subsequent, cached)
make test-integration
# Expected: ✓ 4 tests pass in ~10s (voice cached)

# 4. All tests
make test
# Expected: ✓ 365 tests pass (361 unit + 4 integration)
```

---

## CI Behavior

**First PR** (cold cache):
- Unit tests: ~10s
- Integration tests: ~90s (generates voice)
- Total: ~100s

**Subsequent PRs** (warm cache):
- Unit tests: ~10s
- Integration tests: ~15s (voice cached)
- Total: ~25s (runs in parallel)

---

## Success Criteria

- [ ] All 4 integration tests pass locally
- [ ] `make test-unit` runs fast (< 10s)
- [ ] `make test-integration` builds binary automatically
- [ ] CI jobs run in parallel
- [ ] Voice cache works (second CI run is fast)
- [ ] Artifacts uploaded on failure

---

## Reference Documents

1. **`FINAL_EXECUTION_PLAN.md`** - Complete implementation guide
2. **`EMPIRICAL_TEST_RESULTS.md`** - Validation of all assumptions
3. **`CRITICAL_PATH_GAPS.md`** - Detailed gap analysis

---

## Notes for Implementation

- Suite attribute: `@Suite("...", .serialized)` prevents parallel execution
- All tests use `async throws` functions
- Temp directories use UUID for uniqueness
- Always clean up with `defer { try? FileManager.default.removeItem(...) }`
- Print progress messages for long operations (voice generation)
- Log RMS/Peak values for debugging

---

**Ready to implement!** All critical gaps resolved, all code validated. 🚀
