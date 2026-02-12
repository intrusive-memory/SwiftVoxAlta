# Execution Plan Analysis Report

Generated: 2026-02-12T11:00:00-08:00
Execution plan: /Users/stovak/Projects/SwiftVoxAlta/EXECUTION_PLAN.md
Context budget: 50 turns per sprint

---

## Pass 1: Completeness Analysis

### Point A (Current State)
Status: CLEAR

**Starting state from the plan and codebase:**

1. **Existing test infrastructure:**
   - `Tests/DigaTests/DigaCLIIntegrationTests.swift` exists (294 lines, tests CLI argument parsing only)
   - Library tests exist (DigaEngineTests, DigaVoiceStoreTests, etc.)
   - Total: 229 library tests + 24 CLI tests

2. **Existing CI infrastructure:**
   - `.github/workflows/tests.yml` with 3 jobs:
     - `build`: Builds all targets
     - `integration-tests`: Verifies binary exists, runs --version check
     - `audio-integration`: Shell-based audio generation test (lines 58-130)
   - Shell-based audio test already validates:
     - WAV file generation
     - RIFF/WAVE headers
     - Non-zero PCM data
     - File size > 44 bytes

3. **Build system:**
   - `Makefile` with single `test` target (line 65-66)
   - Binary path: `./bin/diga` (exists, built with `make install`)
   - Models cached in `~/Library/SharedModels/` via SwiftAcervo

4. **Empirical validation completed:**
   - Working directory: `/private/tmp` during tests (Gap 1 resolved)
   - Binary path resolution via `#filePath` validated (Gap 1 resolved)
   - Async/await syntax validated (Gap 3 resolved)
   - RMS/Peak thresholds measured: RMS > 0.02, Peak > 0.1 (Gap 4 resolved)
   - Voice caching strategy chosen: Option B auto-generate (Gap 2 resolved)
   - Build dependency strategy chosen: Option B separate targets (Gap 5 resolved)

**Findings:**
- ✅ Starting state is well-documented
- ✅ All critical gaps from CRITICAL_PATH_GAPS.md have been resolved
- ✅ Empirical validation completed for all technical unknowns

### Point B (Target State)
Status: CLEAR

**End state from the plan:**

1. **New test infrastructure:**
   - `Tests/DigaTests/DigaBinaryIntegrationTests.swift` (~350 lines)
   - 6 test cases:
     - WAV generation (primary test)
     - AIFF generation
     - M4A generation
     - Silence detection (negative test)
     - Binary not found error handling
     - Voice cache warmup
   - Voice auto-generation in `init()` if not cached

2. **Build system updates:**
   - `test-unit`: Fast tests, skips DigaBinaryIntegrationTests
   - `test-integration`: Requires binary, builds if needed
   - `test`: Runs both sequentially

3. **CI updates:**
   - Separate `unit-tests` and `integration-tests` jobs
   - Voice caching: `~/Library/SharedModels` + `~/Library/Caches/intrusive-memory/Voices`
   - Artifact upload on failure

4. **Documentation:**
   - README updated with test instructions
   - Voice cache behavior documented

**Findings:**
- ✅ Target state is clearly specified
- ✅ All deliverables are named and scoped
- ✅ Success criteria are explicit (lines 673-699)

### Coverage Analysis
Status: COMPLETE with 1 OVERLAP

**Requirements mapping:**

| Requirement | Addressed By | Coverage |
|-------------|-------------|----------|
| Swift-based binary integration tests | Phase 7 (test cases) | ✓ Complete |
| Process spawning with timeout | Phase 2 (runDiga) | ✓ Complete |
| Audio file validation | Phase 3, 4, 5 | ✓ Complete |
| Multi-format support (WAV/AIFF/M4A) | Phase 4 (validateAudioHeaders) | ✓ Complete |
| Silence detection | Phase 5 (validateNotSilence) | ✓ Complete |
| Voice caching | Phase 0 (init + warmup) | ✓ Complete |
| Error handling | Phase 6 (TestError enum) | ✓ Complete |
| Build system separation | Makefile Updates section | ✓ Complete |
| CI separation | CI Configuration section | ✓ Complete |
| Documentation | Documentation section | ✓ Complete |

**Gaps:**

1. **OVERLAP with existing CI test** (audio-integration job):
   - Existing shell-based test (lines 58-130 of tests.yml) already validates:
     - Audio generation: `./bin/diga --model 0.6b -o /tmp/test.wav "Hello from CI"`
     - File size: `stat -f%z /tmp/test.wav` (> 44 bytes)
     - RIFF/WAVE header: `xxd` checks at offsets 0 and 8
     - Non-silence: PCM data contains non-zero bytes
   - **New Swift-based test duplicates this validation**
   - Plan does NOT address:
     - Should shell-based test be removed?
     - Should shell-based test remain as a separate validation layer?
     - How do the two tests relate?

2. **Implementation Checklist shows work NOT STARTED:**
   - Lines 705-713: Code tasks [ ] unchecked
   - Lines 716-719: Build system tasks [ ] unchecked
   - Lines 722-726: CI tasks [ ] unchecked
   - Lines 729-730: Documentation tasks [ ] unchecked
   - **All work is pending** - plan is a blueprint, not completed work

**Recommendations:**

1. **Clarify relationship with existing CI test:**
   - Option A: Remove shell-based audio-integration job (replaced by Swift tests)
   - Option B: Keep both (shell for quick smoke test, Swift for comprehensive)
   - Option C: Merge shell test into integration-tests job, keep Swift for local dev

2. **Add explicit file cleanup:**
   - Plan shows `defer { try? FileManager.default.removeItem(...) }` in tests
   - Should add cleanup step to verify no leaked temp files

### Open Questions
Count: 1

| Question | Location | Type | Blocking Impact |
|----------|----------|------|----------------|
| What happens to existing shell-based audio-integration CI job? | tests.yml lines 58-130 | Architectural decision | Does not block implementation, but affects final CI structure |

**Recommendations:**
- **Action**: Decide whether to keep, remove, or merge the existing audio-integration job
- **When**: Before finalizing CI configuration (Sprint 2 if split, or before implementing CI section)
- **Impact**: Low - both approaches work, this is about consistency and maintainability

---

## Pass 2: Atomicity & Testability Analysis

### Atomicity Check

**Plan structure detected:**
- **NOT** structured as sprints
- Structured as 8 phases (0-7) + 4 sections (Makefile, CI, Success Criteria, Implementation Checklist)
- Single work unit: "Audio Generation Integration Test"
- Entire plan is one deliverable unit

**Atomicity evaluation of current plan structure:**

| Sprint | Single Concern | Clear Artifact | Bounded Scope | Explicit I/O | Verdict |
|--------|---------------|---------------|---------------|-------------|---------|
| Entire plan | ❌ FAIL | ✅ PASS | ⚠️ MARGINAL | ✅ PASS | **FAIL: Multiple concerns** |

**Issues: Entire plan as single unit**

**Issue 1: Multiple concerns** (FAIL)

The plan combines 4 distinct concerns:
1. **Test code** (Phases 0-7): Swift test implementation
2. **Build system** (Makefile Updates): Build tooling
3. **CI infrastructure** (CI Configuration): Automation
4. **Documentation** (Files to Create/Modify): User-facing docs

These are separate concerns that could be implemented and verified independently.

**Issue 2: Bounded scope** (MARGINAL)

Estimated turns: 35 (see Context Fitness Check below)
- Context budget: 50 turns
- Utilization: 70% (acceptable but high)
- **Barely fits** in a single sprint

**Issue 3: Clear artifact** (PASS)

All files are explicitly named:
- New: `Tests/DigaTests/DigaBinaryIntegrationTests.swift` (~350 lines)
- Modified: `Makefile` (+15 lines), `.github/workflows/tests.yml` (+40 lines, restructure), `README.md` (+10 lines)

**Issue 4: Explicit I/O** (PASS)

Entry criteria:
- Existing: `Makefile`, `tests.yml`, `README.md`, CLI tests, binary at `./bin/diga`
- Empirical validation results from `docs/EMPIRICAL_TEST_RESULTS.md`

Exit criteria (lines 673-699):
- 12 specific checkboxes covering functional, performance, and quality requirements

**Recommendations:**

**Split into 3 atomic sprints:**

**Sprint 1: Binary Integration Test Implementation**
- Scope: Phases 0-7 only (test code)
- Files: Create `DigaBinaryIntegrationTests.swift`
- Turns: ~20
- Exit: `make test` passes, all 6 test cases passing

**Sprint 2: Build System & CI Updates**
- Scope: Makefile + CI configuration
- Files: Modify `Makefile`, `tests.yml`
- Turns: ~10
- Exit: `make test-unit` and `make test-integration` work, CI passes

**Sprint 3: Documentation**
- Scope: README updates
- Files: Modify `README.md`
- Turns: ~5
- Exit: README has test instructions, voice cache behavior documented

---

### Testability Check

| Sprint | Machine-Verifiable | No Vague Language | Full Coverage | Verdict |
|--------|-------------------|-------------------|--------------|---------|
| Entire plan | ✅ PASS | ✅ PASS | ✅ PASS | **PASS** |

**Machine-verifiable criteria:**
- [x] Binary spawning works from any working directory
- [x] File validation (existence, size, headers)
- [x] Format validation (AVAudioFile, sample rate, channels)
- [x] Silence detection (RMS/Peak thresholds empirically validated)
- [x] Multi-format support (WAV, AIFF, M4A)
- [x] Error handling (binary not found, timeout, invalid format)
- [x] Voice caching (auto-generates on first run)
- [x] Unit tests: < 10 seconds
- [x] Integration tests (warm cache): < 15 seconds
- [x] Integration tests (cold cache): < 90 seconds

**No vague language:**
- All criteria use specific, measurable terms
- Thresholds are empirically validated (RMS > 0.02, Peak > 0.1)
- Performance targets have exact values (< 10s, < 15s, < 90s)

**Full coverage:**
Every task in the Implementation Checklist (lines 705-730) has corresponding exit criteria:
- Code tasks → Functional Requirements (lines 675-685)
- Build system → Performance Targets (lines 687-692)
- CI → Performance + Quality Metrics (lines 687-699)
- Documentation → Success Criteria section

**Verdict: TESTABLE** - Exit criteria are clear, specific, and machine-verifiable.

---

### Context Fitness Check

| Sprint | Estimated Turns | Budget | Utilization | Verdict |
|--------|----------------|--------|-------------|---------|
| Entire plan | 35 | 50 | 70% | **Right-sized** (but see atomicity concerns) |

**Turn estimation formula:**
```
estimated_turns = R + (C * 2) + (M * 2) + B + ceil(L / 75) + V + 5
```

**Breakdown:**

- **R** (files to read): 4
  - Existing `Makefile` (89 lines)
  - Existing `tests.yml` (131 lines)
  - Existing `README.md` (100 lines)
  - Empirical results `docs/EMPIRICAL_TEST_RESULTS.md` (reference)
  - **Total: 4 reads**

- **C** (files to create): 1
  - `Tests/DigaTests/DigaBinaryIntegrationTests.swift` (~350 lines)
  - **Total: 1 × 2 = 2 turns**

- **M** (files to modify): 3
  - `Makefile` (+15 lines)
  - `.github/workflows/tests.yml` (+40 lines, restructure existing jobs)
  - `README.md` (+10 lines)
  - **Total: 3 × 2 = 6 turns**

- **B** (build/compile steps): 3
  - `make test-unit` (verify unit tests work)
  - `make test-integration` (verify integration tests work)
  - `make test` (verify combined target works)
  - **Total: 3 turns**

- **L** (lines of code to write): 415
  - New test file: 350 lines
  - Makefile additions: 15 lines
  - CI additions: 40 lines
  - README additions: 10 lines
  - **Total: ceil(415 / 75) = 6 turns**

- **V** (verification steps): 12
  - From Implementation Checklist (lines 705-730)
  - **Total: 12 turns**

- **Fixed overhead**: 5 turns

**Total: 4 + 2 + 6 + 3 + 6 + 12 + 5 = 38 turns**

**Verdict:**
- Estimated: 38 turns
- Budget: 50 turns
- Utilization: 76%
- **Right-sized for a single sprint** (fits in budget)

**However, combining with atomicity concerns:**
- Plan is NOT atomic (multiple concerns)
- Plan DOES fit in context budget (76% utilization)
- **Recommendation: Split into 3 smaller sprints** for better atomicity, even though it fits in one sprint

**Budget Summary:**
- Total turns across plan (as single unit): 38
- Average utilization: 76%
- Oversized sprints: 0
- Undersized sprints: 0
- **Conclusion: Right-sized but should split for atomicity**

---

## Pass 3: Priority & Parallelism Analysis

### Dependency Graph

**Critical Path:** Single work unit plan → no cross-unit dependencies

**Internal phase dependencies:**
```
Phase 0 (Voice warmup init)
    ↓
Phase 1 (Binary path resolution) ─┐
Phase 2 (Process spawning)        ├─→ Phase 7 (Test cases)
Phase 3 (File validation)         │
Phase 4 (Audio format validation) │
Phase 5 (Silence detection)       │
Phase 6 (Error types)            ─┘
    ↓
Makefile Updates
    ↓
CI Configuration Updates
    ↓
Documentation
```

**Bottlenecks:**
- Phase 7 (Test cases) blocks all downstream work (Makefile, CI, docs)
- Phases 1-6 are independent helpers that could be implemented in parallel
- No single bottleneck sprint (linear dependency chain)

---

### Parallelization Opportunities

**Current Parallelism:** 1 (single work unit, sequential phases)

**Maximum Parallelism:** 1 (cannot parallelize phases within a single file)

**Missed Opportunities:**

None for the current plan structure. However, if split into multiple sprints:

**Potential parallel work (if split):**
1. **Sprint 1 (Test code)** and **Sprint 3 (Documentation)** could run in parallel
   - Documentation can be written based on the plan without waiting for implementation
   - Would save ~5 turns overall
2. **Sprint 2 (Build/CI)** depends on Sprint 1 completing (needs test code to exist)

**Recommendation:**
- If keeping as single sprint: no parallelization possible
- If splitting into 3 sprints: Sprints 1 and 3 could run in parallel

---

### Priority Analysis

| Sprint | Priority Score | Current Position | Optimal Position | Recommendation |
|--------|---------------|-----------------|------------------|----------------|
| Entire plan | 3.34 | 1 (only sprint) | N/A | Low priority (leaf sprint) |

**Priority score breakdown:**

```
priority = (dependency_depth * 3) + (foundation_score * 2) + (risk_level * 1) + (complexity * 0.5)
```

**Dependency depth:** 0
- No other work units depend on this
- This is a "leaf" sprint (adds tests but doesn't establish foundational types)
- Score: 0 × 3 = 0

**Foundation score:** 0
- Does NOT establish types, interfaces, or patterns reused by other sprints
- Adds test coverage but doesn't create shared abstractions
- Score: 0 × 2 = 0

**Risk level:** 2 (medium risk)
- Indicators:
  - File I/O (2 points): Reading/writing audio files
  - System calls (2 points): Process spawning, subprocess management
  - No external API calls (would be 3 points)
  - No new/unfamiliar technology (empirical validation completed)
- Highest indicator: 2 (file I/O + system calls)
- Score: 2 × 1 = 2

**Complexity:** 2.67 (medium-high complexity)
- Task count: 7 phases → 3 points (6-7 tasks)
- Files touched: 4 files (1 new + 3 modified) → 2 points (3-5 files)
- Verification complexity: 12 criteria, mix of build/test/format checks → 3 points (integration tests)
- Average: (3 + 2 + 3) / 3 = 2.67
- Score: 2.67 × 0.5 = 1.34

**Total Priority: 0 + 0 + 2 + 1.34 = 3.34**

**Priority classification:** LOW (typical range: 1-15, this is at low end)

**Rationale:**
- This is a quality/testing enhancement, not a foundational feature
- No other work depends on this completing
- Moderate risk and complexity but no blocking impact
- Should be executed AFTER higher-priority foundation work

---

### Execution Order Recommendations

**Foundation-first check:** N/A (single work unit plan)

**Risk-early check:** ✅ PASS
- Medium risk (2 points), but empirical validation completed
- All technical unknowns resolved before planning
- Risk is well-managed

**Bottleneck-early check:** N/A (no bottlenecks, linear dependency chain)

**Proposed Execution Order (if split into 3 sprints):**

| Current | Proposed | Sprint | Rationale |
|---------|----------|--------|-----------|
| 1 | 1 | Test Implementation | Foundation for build/CI |
| 2 | 2 | Build & CI | Depends on tests existing |
| 3 | 3 | Documentation | Depends on implementation complete |

**No reordering needed** - natural dependency order is already optimal.

---

## Summary

### Overall Assessment

| Pass | Status | Issues | Recommendations |
|------|--------|--------|----------------|
| Completeness | ✅ PASS | 1 overlap | Clarify relationship with existing CI test |
| Atomicity & Testability | ⚠️ NEEDS_WORK | 1 major | Split into 3 sprints for atomicity |
| Priority & Parallelism | ✅ PASS | 0 | Execution order is optimal |

**Total Issues Found:** 2 (1 overlap, 1 atomicity)

**Critical Issues** (must address before execution):
- None - plan is executable as-is

**Recommended Issues** (improve execution quality):
1. **Split plan into 3 atomic sprints** (major atomicity concern)
   - Current: Single 38-turn sprint with 4 concerns
   - Recommended: 3 sprints (~20 + ~10 + ~5 turns each)
   - Benefit: Better separation of concerns, easier verification, more resilient to failures

2. **Clarify overlap with existing CI test** (minor architectural concern)
   - Current: Shell-based audio-integration job in CI does similar validation
   - Recommended: Decide to keep/remove/merge before finalizing CI section
   - Benefit: Avoid duplicate validation, clearer CI structure

**Optional Improvements:**
- None - plan is well-structured and thoroughly validated

---

### Next Steps

**Automated fixes available:**
- ❌ **NO automated fixes** - This plan is prescriptive code (not a typical sprint plan)
- Manual refactoring needed to split into multiple sprints

**Manual review needed:**

1. **RECOMMENDED: Refactor into 3 sprints**
   - Sprint 1: "Implement Binary Integration Tests" (test code only)
   - Sprint 2: "Add Build System & CI Support" (Makefile + tests.yml)
   - Sprint 3: "Document Testing Workflow" (README updates)
   - After refactoring: re-run `/sprint-supervisor analyze`

2. **RECOMMENDED: Clarify CI overlap**
   - Review existing audio-integration job (tests.yml lines 58-130)
   - Decide: keep both, remove shell test, or merge into integration-tests job
   - Update plan with decision

3. **OPTIONAL: Proceed as single sprint**
   - Plan fits in context budget (76% utilization)
   - All decisions made, empirical validation complete
   - Ready for `/sprint-supervisor start`
   - **Trade-off:** Less atomic (4 concerns in one sprint) but faster overall

**If proceeding as single sprint (Option 3):**
- ✅ All critical gaps resolved
- ✅ All empirical validation complete
- ✅ Exit criteria are clear and testable
- ✅ Context budget is adequate (38/50 turns)
- ⚠️ Sprint is not atomic (4 concerns) but manageable
- 🚀 **Ready for `/sprint-supervisor start`**

**If refactoring into 3 sprints (Recommended):**
1. Create separate sprint definitions for test code, build/CI, and docs
2. Define entry/exit criteria for each sprint
3. Re-run `/sprint-supervisor analyze` to validate new structure
4. Then proceed to `/sprint-supervisor start`

---

## Detailed Findings

### Issue 1: Plan structure is not atomic (multiple concerns)

**Location:** Entire plan structure (Phases 0-7 + Makefile + CI + Documentation sections)

**Type:** Atomicity

**Severity:** Recommended (not blocking, but reduces resilience and clarity)

**Problem:**

The plan combines 4 distinct concerns into a single unit:

1. **Test code** (Phases 0-7, ~350 lines):
   - Voice warmup (`init()`, `areVoicesCached()`)
   - Binary path resolution (`findBinaryPath()`)
   - Process spawning (`runDiga()`)
   - Validation helpers (`validateFileExists()`, `validateAudioHeaders()`, `validateAudioFormat()`, `validateNotSilence()`)
   - Error types (`TestError` enum)
   - Test cases (WAV, AIFF, M4A, error handling)

2. **Build system** (Makefile Updates section, +15 lines):
   - `test-unit` target
   - `test-integration` target
   - Combined `test` target

3. **CI infrastructure** (CI Configuration Updates section, +40 lines):
   - Restructure existing jobs
   - Add separate `unit-tests` job
   - Add separate `integration-tests` job
   - Add voice caching
   - Add artifact upload

4. **Documentation** (Files to Create/Modify section, +10 lines):
   - README updates
   - Test instructions
   - Voice cache behavior

These concerns are **independent** and could be implemented, verified, and committed separately.

**Impact:**

- Increases sprint complexity (4 distinct deliverables in one sprint)
- Makes verification harder (must verify all 4 concerns together)
- Reduces error recovery (if one concern fails, entire sprint fails)
- Harder to parallelize work (all concerns coupled in single sprint)

**Recommendation:**

**Split into 3 atomic sprints:**

**Sprint 1: Implement Binary Integration Tests**
```markdown
## Sprint 1: Implement Binary Integration Tests

**Entry criteria:**
- [x] Empirical validation complete (EMPIRICAL_TEST_RESULTS.md)
- [x] All critical gaps resolved (Gap 1-5)
- [x] Binary exists at ./bin/diga

**Tasks:**
1. Create `Tests/DigaTests/DigaBinaryIntegrationTests.swift`
2. Implement voice warmup (`init()`, `areVoicesCached()`)
3. Implement binary path resolution (`findBinaryPath()`)
4. Implement process spawning (`runDiga()` with async/await + timeout)
5. Implement validation helpers:
   - `validateFileExists()`
   - `validateAudioHeaders()` (WAV/AIFF/M4A)
   - `validateAudioFormat()` (AVAudioFile checks)
   - `validateNotSilence()` (RMS/Peak analysis)
6. Implement `TestError` enum
7. Implement test cases:
   - `wavGeneration()` (primary test)
   - `aiffGeneration()`
   - `m4aGeneration()`
   - `binaryNotFoundHandling()`

**Exit criteria:**
- [x] File exists: `Tests/DigaTests/DigaBinaryIntegrationTests.swift`
- [x] All 4 test cases pass (WAV, AIFF, M4A, error handling)
- [x] Voice auto-generation works on first run
- [x] Audio validation passes (file size, headers, format, non-silence)
- [x] Build succeeds: `xcodebuild build-for-testing -scheme SwiftVoxAlta-Package`
- [x] Tests pass: `xcodebuild test -scheme SwiftVoxAlta-Package -only-testing:DigaTests/DigaBinaryIntegrationTests`

**Estimated turns:** 20
```

**Sprint 2: Add Build System & CI Support**
```markdown
## Sprint 2: Add Build System & CI Support

**Entry criteria:**
- [x] Sprint 1 complete (DigaBinaryIntegrationTests.swift exists and passes)
- [x] Binary exists at ./bin/diga

**Tasks:**
1. Update `Makefile`:
   - Add `test-unit` target (skips DigaBinaryIntegrationTests)
   - Add `test-integration` target (builds binary, runs integration tests)
   - Update `test` target (runs both sequentially)
2. Update `.github/workflows/tests.yml`:
   - Restructure into separate `unit-tests` and `integration-tests` jobs
   - Add voice caching (`~/Library/SharedModels`, `~/Library/Caches/intrusive-memory/Voices`)
   - Add artifact upload on failure
   - Optionally: remove or merge existing `audio-integration` job

**Exit criteria:**
- [x] `make test-unit` runs fast (< 10 seconds), skips binary tests
- [x] `make test-integration` builds binary and runs integration tests
- [x] `make test` runs both targets sequentially
- [x] CI `unit-tests` job passes
- [x] CI `integration-tests` job passes
- [x] Voice cache works in CI (subsequent runs use cached voices)

**Estimated turns:** 10
```

**Sprint 3: Document Testing Workflow**
```markdown
## Sprint 3: Document Testing Workflow

**Entry criteria:**
- [x] Sprint 1 complete (tests exist)
- [x] Sprint 2 complete (Makefile + CI updated)

**Tasks:**
1. Update `README.md`:
   - Add "Running Tests" section
   - Document `make test-unit` vs `make test-integration`
   - Document voice cache behavior (auto-generates on first run)
   - Document first-run timing expectations (< 90s with voice generation)

**Exit criteria:**
- [x] README has "Running Tests" section
- [x] README documents `make test-unit` and `make test-integration`
- [x] README documents voice cache behavior
- [x] README is accurate (verify instructions work)

**Estimated turns:** 5
```

**Benefits of splitting:**
1. **Better atomicity:** Each sprint has a single concern
2. **Easier verification:** Clear exit criteria per sprint
3. **Better error recovery:** If Sprint 2 fails, Sprint 1's tests are still committed
4. **Potential parallelization:** Sprint 3 (docs) could start while Sprint 2 (build/CI) is in progress
5. **Clearer progress tracking:** 3 completion events vs 1 monolithic completion

---

### Issue 2: Overlap with existing shell-based CI test

**Location:** `.github/workflows/tests.yml` lines 58-130 (audio-integration job)

**Type:** Architectural decision

**Severity:** Optional (does not block execution, affects final CI structure)

**Problem:**

The existing CI configuration has a shell-based `audio-integration` job that validates:
- Audio generation: `./bin/diga --model 0.6b -o /tmp/test.wav "Hello from CI"`
- File size: `stat -f%z /tmp/test.wav` (> 44 bytes)
- RIFF/WAVE header: `xxd` checks at offsets 0 and 8
- Non-silence: PCM data contains non-zero bytes

The new Swift-based `DigaBinaryIntegrationTests` validates:
- Audio generation (same: spawns diga binary)
- File existence and size (same: > 44 bytes for WAV)
- Audio headers (same: RIFF/WAVE magic bytes)
- Non-silence (enhanced: RMS/Peak analysis vs simple non-zero check)

**Overlap:**
- Both tests spawn the binary and generate audio
- Both validate basic file format
- Both check for non-silence
- New test is more comprehensive (RMS/Peak analysis, multi-format, error cases)

**Impact:**

- CI runs duplicate validation (shell + Swift)
- Increased CI time (both tests download models, generate audio)
- Potential confusion: which test is authoritative?
- Maintenance burden: two places to update audio validation

**Recommendation:**

**Choose one of three options:**

**Option A: Remove shell-based audio-integration job** (Recommended)
```yaml
# Remove lines 58-130 of tests.yml
# Rationale:
# - Swift tests are more comprehensive
# - Swift tests cover all the same checks + more
# - Reduces duplication and CI time
# - Single source of truth for audio validation
```

**Option B: Keep both tests (layered validation)**
```yaml
# Keep audio-integration job as quick smoke test (< 30s)
# Keep DigaBinaryIntegrationTests as comprehensive suite (< 90s)
# Rationale:
# - Shell test runs early, fails fast on basic issues
# - Swift tests run later, comprehensive validation
# - Defense in depth (catch issues at multiple levels)
```

**Option C: Merge shell test into integration-tests job**
```yaml
# Remove standalone audio-integration job
# Add audio validation steps to integration-tests job (lines 28-57)
# Steps:
#   - Build binary (already exists)
#   - Synthesize test audio (from audio-integration)
#   - Validate WAV (from audio-integration)
#   - Run Swift integration tests (new)
# Rationale:
# - Single job for all integration validation
# - Faster overall (shares binary build step)
# - Shell test acts as pre-check before Swift tests
```

**Decision needed:**
- Review existing audio-integration job
- Choose Option A, B, or C based on CI goals (speed vs defense-in-depth)
- Update plan with decision before implementing Sprint 2 (CI updates)

**If no decision made:**
- Default: Keep both tests (Option B)
- Trade-off: Slightly longer CI time but more validation coverage
