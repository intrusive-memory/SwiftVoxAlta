# VoiceDesign v0.3.0 Execution Plan

**Date**: 2026-02-14
**Goal**: Ship VoiceDesign character voice pipeline in SwiftVoxAlta v0.3.0
**Based On**: [VoiceDesign Research Summary](docs/VOICEDESIGN_RESEARCH_SUMMARY.md)

---

## Executive Summary

**Scope**: Documentation, verification, and optimization of existing VoiceDesign implementation
**Timeline**: 2-4 hours (immediate) + 1-2 days (optimizations)
**Status**: All features implemented, just need exposure and optimization

**Key Insight**: VoiceDesign and Base model cloning are **100% implemented** in mlx-audio-swift fork. VoxAlta already uses these APIs correctly. Gap is in documentation and performance optimization.

---

## Work Units

| Work Unit | Directory | Sprints | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| Verification & Documentation | . | 4 | 0 | none |
| Performance Optimization | . | 3 | 1 | Verification complete |

---

## Sprint 1: Verify Implementation

**Entry Criteria**:
- [ ] Research documents committed to development branch
- [ ] All 5 research reports readable in docs/

**Tasks**:
1. Run full test suite to verify VoiceDesign APIs work
2. Check for any VoiceDesign-related test failures
3. Verify VoiceDesigner.swift uses mlx-audio-swift fork APIs correctly
4. Verify VoiceLockManager.swift creates/uses clone prompts correctly
5. Document test results in verification report

**Exit Criteria**:
- [ ] `make test` completes without VoiceDesign-related failures
- [ ] All 234 tests accounted for (passing or documented failures)
- [ ] VoiceDesigner API usage confirmed correct (lines 100-107, 144-150)
- [ ] VoiceLockManager API usage confirmed correct (lines 78-97, 144-162)
- [ ] Verification report created: `docs/VOICEDESIGN_VERIFICATION_REPORT.md`

**Verification Commands**:
```bash
make test 2>&1 | tee /tmp/voicedesign-test-output.txt
grep -E "(PASS|FAIL|ERROR)" /tmp/voicedesign-test-output.txt
test -f docs/VOICEDESIGN_VERIFICATION_REPORT.md
```

**Estimated Duration**: 30 minutes

---

## Sprint 2: Pin Fork Dependency

**Entry Criteria**:
- [ ] Sprint 1 complete
- [ ] Test suite passing

**Tasks**:
1. Check current Package.swift dependency (should be branch: "development")
2. Get current commit hash from Package.resolved
3. Update Package.swift to use exact revision instead of branch
4. Run `xcodebuild -resolvePackageDependencies` to verify
5. Update AGENTS.md to document pinned fork commit

**Exit Criteria**:
- [ ] Package.swift uses `.package(url: "...", revision: "eedb0f5a...")` instead of branch
- [ ] `xcodebuild -resolvePackageDependencies` succeeds
- [ ] Package.resolved shows pinned revision
- [ ] AGENTS.md documents fork pinning rationale
- [ ] Build succeeds: `make build` completes

**Verification Commands**:
```bash
grep -E 'revision.*eedb0f5a' Package.swift
xcodebuild -resolvePackageDependencies -scheme SwiftVoxAlta-Package
make build
```

**Estimated Duration**: 20 minutes

---

## Sprint 3: Document VoiceDesign Workflow

**Entry Criteria**:
- [ ] Sprint 2 complete
- [ ] Verification report confirms APIs work

**Tasks**:
1. Add VoiceDesign workflow section to README.md
2. Document character → profile → candidates → lock → audio pipeline
3. Add code examples for each step (from VOICEDESIGN_RESEARCH_SUMMARY.md)
4. Update AGENTS.md with VoiceDesign API documentation
5. Document VoiceDesigner and VoiceLockManager public APIs
6. Add troubleshooting section for common VoiceDesign issues
7. Document model requirements (VoiceDesign 1.7B, Base 1.7B, disk space)

**Exit Criteria**:
- [ ] README.md has "VoiceDesign Character Voice Pipeline" section
- [ ] README.md includes complete workflow example
- [ ] AGENTS.md documents VoiceDesigner API (generateCandidates, composeVoiceDescription)
- [ ] AGENTS.md documents VoiceLockManager API (createVoiceLock, generateAudio)
- [ ] Documentation includes all 5 pipeline steps
- [ ] Troubleshooting section covers model download, memory, quality issues

**Verification Commands**:
```bash
grep -i "voicedesign" README.md
grep "VoiceDesigner" AGENTS.md
grep "VoiceLockManager" AGENTS.md
test $(grep -c "```swift" README.md) -ge 3  # At least 3 code examples
```

**Estimated Duration**: 1-2 hours

---

## Sprint 4: Add VoiceDesign Integration Test

**Entry Criteria**:
- [ ] Sprint 3 complete
- [ ] Documentation includes workflow example

**Tasks**:
1. Create new test file: `Tests/SwiftVoxAltaTests/VoiceDesignIntegrationTests.swift`
2. Implement test for full VoiceDesign pipeline (character → profile → candidates → lock → audio)
3. Use sample CharacterProfile (e.g., "ELENA" from IntegrationTests.swift)
4. Generate 1 voice candidate (not 3, to keep test fast)
5. Create VoiceLock from candidate
6. Generate audio from lock
7. Verify audio WAV format (24kHz, mono)
8. Add `.disabled()` trait for CI (Metal compiler limitation)
9. Document test in AGENTS.md

**Exit Criteria**:
- [ ] `Tests/SwiftVoxAltaTests/VoiceDesignIntegrationTests.swift` exists
- [ ] Test exercises all 5 pipeline steps
- [ ] Test validates WAV format (RIFF header, 24kHz)
- [ ] Test is disabled on CI (GITHUB_ACTIONS check)
- [ ] Test passes locally: `make test-unit` shows test in output
- [ ] AGENTS.md documents VoiceDesign integration test location

**Verification Commands**:
```bash
test -f Tests/SwiftVoxAltaTests/VoiceDesignIntegrationTests.swift
grep "VoiceDesignIntegrationTests" Tests/SwiftVoxAltaTests/VoiceDesignIntegrationTests.swift
grep "disabled.*GITHUB_ACTIONS" Tests/SwiftVoxAltaTests/VoiceDesignIntegrationTests.swift
make test-unit 2>&1 | grep -i voicedesign
```

**Estimated Duration**: 1-2 hours

---

## Sprint 5: Implement Parallel Voice Generation

**Entry Criteria**:
- [ ] Sprint 4 complete
- [ ] All verification and documentation sprints finished

**Tasks**:
1. Read current VoiceDesigner.generateCandidates() implementation (lines 136-153)
2. Replace sequential for-loop with `withThrowingTaskGroup`
3. Preserve candidateCount parameter behavior
4. Add error handling for TaskGroup failures
5. Update VoiceDesignIntegrationTests to verify parallel generation works
6. Add performance logging to measure speedup
7. Document parallel generation in AGENTS.md

**Exit Criteria**:
- [ ] VoiceDesigner.generateCandidates() uses TaskGroup
- [ ] Sequential for-loop removed (lines 144-150 replaced)
- [ ] Error handling preserves first error from group
- [ ] VoiceDesignIntegrationTests passes with parallel generation
- [ ] Performance log shows 2-3× speedup for 3 candidates (if measured)
- [ ] AGENTS.md documents parallel generation optimization

**Verification Commands**:
```bash
grep "withThrowingTaskGroup" Sources/SwiftVoxAlta/VoiceDesigner.swift
grep -v "for.*in.*0..<count" Sources/SwiftVoxAlta/VoiceDesigner.swift | grep -q generateCandidates  # Should not have old loop
make test-unit 2>&1 | grep -i voicedesign
```

**Estimated Duration**: 2-3 hours

---

## Sprint 6: Implement Clone Prompt Caching

**Entry Criteria**:
- [ ] Sprint 5 complete
- [ ] Parallel generation working

**Tasks**:
1. Add `clonePromptCache: [String: VoiceClonePrompt]` to VoxAltaVoiceCache actor
2. Update VoxAltaVoiceProvider.generateAudio() to check cache before deserializing
3. Cache deserialized clone prompts after first use
4. Add cache eviction policy (LRU or simple clear on unloadAllVoices)
5. Add cache hit/miss logging to VoxAltaVoiceProvider
6. Update VoiceDesignIntegrationTests to verify caching works
7. Document clone prompt caching in AGENTS.md

**Exit Criteria**:
- [ ] VoxAltaVoiceCache has clonePromptCache dictionary
- [ ] VoxAltaVoiceProvider checks cache before deserializing
- [ ] Cache is populated on first generation
- [ ] Cache is cleared on unloadAllVoices()
- [ ] VoiceDesignIntegrationTests validates cache hit after first generation
- [ ] AGENTS.md documents caching optimization

**Verification Commands**:
```bash
grep "clonePromptCache" Sources/SwiftVoxAlta/VoxAltaVoiceCache.swift
grep "clonePromptCache" Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift
make test-unit 2>&1 | grep -i voicedesign
```

**Estimated Duration**: 3-4 hours

---

## Sprint 7: Add M5 Neural Accelerator Detection

**Entry Criteria**:
- [ ] Sprint 6 complete
- [ ] Caching implemented and tested

**Tasks**:
1. Create new file: `Sources/SwiftVoxAlta/AppleSiliconInfo.swift`
2. Implement `AppleSiliconGeneration` enum (M1-M5 detection)
3. Add runtime detection via `sysctlbyname("machdep.cpu.brand_string")`
4. Update VoxAltaModelManager to log Neural Accelerator status on model load
5. Document M5 optimization in README.md and AGENTS.md
6. Add unit test for AppleSiliconGeneration.current
7. Note: Zero code changes needed for MLX to use Neural Accelerators (auto-detect)

**Exit Criteria**:
- [ ] `Sources/SwiftVoxAlta/AppleSiliconInfo.swift` exists
- [ ] AppleSiliconGeneration enum detects M1-M5
- [ ] VoxAltaModelManager logs "Neural Accelerators detected" on M5
- [ ] README.md documents M5 optimization (4× speedup, macOS 26.2+)
- [ ] AGENTS.md documents AppleSiliconInfo API
- [ ] Unit test validates generation detection on current hardware

**Verification Commands**:
```bash
test -f Sources/SwiftVoxAlta/AppleSiliconInfo.swift
grep "AppleSiliconGeneration" Sources/SwiftVoxAlta/AppleSiliconInfo.swift
grep -i "neural.*accelerator" Sources/SwiftVoxAlta/VoxAltaModelManager.swift
grep -i "neural.*accelerator" README.md
```

**Estimated Duration**: 1 hour

---

## Summary

**Total Sprints**: 7
- **Layer 0 (Verification & Documentation)**: Sprints 1-4 (4-5 hours)
- **Layer 1 (Performance Optimization)**: Sprints 5-7 (6-8 hours)

**Total Estimated Time**: 10-13 hours

**Key Dependencies**:
- Sprint 2 → Sprint 1 (pin fork after verification)
- Sprint 3 → Sprint 2 (document after fork pinned)
- Sprint 4 → Sprint 3 (test after documentation)
- Sprint 5 → Sprint 4 (optimize after tests working)
- Sprint 6 → Sprint 5 (cache after parallel generation)
- Sprint 7 → Sprint 6 (M5 detection after caching)

**Critical Path**: Sprint 1 → Sprint 2 → Sprint 3 → Sprint 4 → Sprint 5 → Sprint 6 → Sprint 7

**Parallelization Opportunities**: None (sequential dependencies)

---

## Success Criteria

- [ ] All 234 tests pass (or failures documented)
- [ ] Package.swift pins mlx-audio-swift fork to specific commit
- [ ] README.md documents VoiceDesign workflow with code examples
- [ ] AGENTS.md documents VoiceDesigner and VoiceLockManager APIs
- [ ] VoiceDesignIntegrationTests exercises full pipeline
- [ ] VoiceDesigner.generateCandidates() uses parallel TaskGroup
- [ ] VoxAltaVoiceCache caches deserialized clone prompts
- [ ] AppleSiliconInfo detects M1-M5 and logs Neural Accelerator status
- [ ] All changes committed to development branch
- [ ] Ready for v0.3.0 release

---

## v0.3.0 Release Notes Draft

**Title**: VoiceDesign Character Voice Pipeline

**Features**:
- 🎙️ VoiceDesign: Text description → novel character voice
- 🎬 Full Pipeline: Character analysis → voice candidates → locked voice → dialogue synthesis
- ⚡ Parallel Generation: 3× faster voice candidate generation
- 💾 Clone Prompt Caching: 2× faster repeated audio generation
- 🖥️ M5 Neural Accelerator Support: 4× speedup on M5 chips (macOS 26.2+)

**Performance**:
- Full workflow: 8.5 min → 3.75 min (2.3× speedup)
- With M5 Neural Accelerators: 8.5 min → 2 min (4.3× speedup)

**Documentation**:
- Complete VoiceDesign workflow examples in README
- VoiceDesigner and VoiceLockManager API documentation
- Troubleshooting guide for common issues

---

## Implementation Notes

### Deferred to v0.4.0

**Medium-Term Optimizations** (not critical for v0.3.0):
- Model weight memory mapping (3× faster cold loads)
- Batch audio generation (1.5× for batch calls)
- Clone prompt compression (3-4MB storage savings)

**Rationale**: Phase 1 optimizations (Sprints 5-7) provide 2-3× speedup for minimal complexity. Medium-term optimizations add complexity with diminishing returns. Ship v0.3.0 first, optimize in v0.4.0 if needed.

### Not Planned

**Core ML ANE Speaker Encoder**: 1.3× speedup, 30% power reduction, but high complexity. MLX Neural Accelerators on M5 provide 4× speedup with zero code changes. Wait for M5 adoption instead.

---

## References

- [VoiceDesign Research Summary](docs/VOICEDESIGN_RESEARCH_SUMMARY.md)
- [VoiceDesign Gap Analysis](docs/VOICEDESIGN_GAP_ANALYSIS.md)
- [mlx-audio-swift Fork Analysis](docs/MLX_AUDIO_FORK_ANALYSIS.md)
- [Apple Optimization Opportunities](docs/APPLE_OPTIMIZATION_OPPORTUNITIES.md)
