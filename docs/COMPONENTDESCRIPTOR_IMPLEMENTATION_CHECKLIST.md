# ComponentDescriptor Implementation Checklist

**For**: Engineers adopting the ComponentDescriptor pattern  
**Reference**: SwiftVoxAlta (Production Reference Implementation)  
**Duration**: ~2-3 hours total (all 5 phases)

---

## Overview

This checklist breaks down the ComponentDescriptor adoption into 5 phases with clear success criteria and estimated effort per phase. Use this to plan your sprint and track progress.

---

## Phase 1: Planning & Discovery

**Estimated Duration**: 30 minutes  
**Effort Level**: Low (analysis only, no code changes)

### 1.1 Identify All Model Variants

- [ ] List all model variants your library supports
- [ ] Map each variant to its HuggingFace repository ID
- [ ] Verify repository IDs are correct (test downloads if needed)
- [ ] Identify any deprecated or legacy models
- [ ] Document any planned model additions

**Success Criteria**:
- [ ] Complete list of all variants (≥2 models)
- [ ] HuggingFace repo IDs verified accessible
- [ ] Deprecated models clearly marked

### 1.2 Document File Requirements

- [ ] List all required files for model loading (from config, code inspection, or HF repo)
- [ ] Verify files are consistent across all variants
- [ ] Determine if different variants need different file lists
- [ ] Check for optional vs. required files

**Success Criteria**:
- [ ] Complete file list (≥8 files expected for ML models)
- [ ] Same file list applies to all variants (typical case)
- [ ] Alternative file lists documented if variants differ

### 1.3 Calculate Memory Requirements

- [ ] Note actual model size (download size in bytes)
- [ ] Determine memory headroom multiplier:
  - Analyze memory spikes during model loading
  - Check for KV caches, activation tensors, overhead
  - Reference VoxAlta's 1.5x multiplier as baseline
- [ ] Calculate: `minimumMemoryBytes = modelSizeBytes × headroomMultiplier`
- [ ] Document headroom multiplier and rationale

**Success Criteria**:
- [ ] Memory requirement calculated for each variant
- [ ] Headroom multiplier documented (e.g., "1.5x for KV caches")
- [ ] Fallback estimates available if exact values unknown

### 1.4 Plan Deprecation Strategy (if applicable)

- [ ] Identify any models planned for deprecation
- [ ] Plan timeline for removal
- [ ] Decide on metadata flags for deprecated variants
- [ ] Document migration path for users

**Success Criteria**:
- [ ] Deprecation list (if any) with timelines
- [ ] Migration guidance written
- [ ] Metadata approach decided

---

## Phase 2: Code Structure

**Estimated Duration**: 1 hour  
**Effort Level**: Medium (new code, straightforward pattern)

### 2.1 Create Model Enumeration

- [ ] Create `enum YourModelRepo: String, CaseIterable, Sendable`
- [ ] Add `.rawValue` for each variant (HuggingFace repo ID)
- [ ] Implement `displayName` computed property
- [ ] Implement `componentId` computed property
- [ ] Add helper methods (slug, size descriptor, etc. if needed)
- [ ] Verify enum compiles without errors

**Success Criteria**:
- [ ] Enum defined with all 7 or more cases
- [ ] `CaseIterable` and `Sendable` conformances present
- [ ] No compiler errors
- [ ] Each case has unique `displayName` and `componentId`

**Reference**: SwiftVoxAlta lines 17–122

### 2.2 Declare Required Files Array

- [ ] Create `private let yourModelRequiredFiles: [ComponentFile]`
- [ ] Add `ComponentFile(relativePath: "...")` for each required file
- [ ] Verify file paths match actual HuggingFace repo structure
- [ ] Test one file path by manually checking HF repo
- [ ] Add comment explaining what each file is used for

**Success Criteria**:
- [ ] Array declared (not nil, not empty)
- [ ] ≥8 ComponentFile entries
- [ ] File paths verified correct
- [ ] Array is `private` (not exposed in public API)

**Reference**: SwiftVoxAlta lines 130–143

### 2.3 Create ComponentDescriptor Array

- [ ] Create `private let yourModelComponentDescriptors: [ComponentDescriptor]`
- [ ] Add one `ComponentDescriptor` per model variant
- [ ] Fill in all required fields:
  - `id`: Use `YourModelRepo.XXX.componentId`
  - `type`: `.languageModel` (or appropriate type)
  - `displayName`: Use `YourModelRepo.XXX.displayName`
  - `repoId`: Use `YourModelRepo.XXX.rawValue`
  - `files`: Use `yourModelRequiredFiles` array
  - `estimatedSizeBytes`: Actual model size in bytes
  - `minimumMemoryBytes`: Size × headroom multiplier
  - `metadata`: `["deprecated": "true"]` for old models only
- [ ] Verify each descriptor compiles
- [ ] Verify `estimatedSizeBytes < minimumMemoryBytes` (multiplier applied)

**Success Criteria**:
- [ ] One descriptor per model variant (≥2 descriptors)
- [ ] All required fields populated
- [ ] No compiler errors
- [ ] Memory bytes ≥ estimated size bytes (multiplier applied)
- [ ] Deprecated models have `metadata: ["deprecated": "true"]`

**Reference**: SwiftVoxAlta lines 149–217

### 2.4 Create Lazy Registration Initializer

- [ ] Create module-level lazy let:
  ```swift
  private let _registerYourModelComponents: Void = {
    Acervo.register(yourModelComponentDescriptors)
  }()
  ```
- [ ] Verify it compiles
- [ ] Add explanatory comment

**Success Criteria**:
- [ ] Lazy let defined at module level (before manager class)
- [ ] Calls `Acervo.register()` with your descriptor array
- [ ] No compiler errors
- [ ] Comment explains "executed once on first access"

**Reference**: SwiftVoxAlta lines 225–227

### 2.5 Trigger Registration in Manager Init

- [ ] Modify your manager's `init()` method
- [ ] Add line: `_ = _registerYourModelComponents`
- [ ] Verify it compiles
- [ ] Add comment explaining why this line is needed

**Success Criteria**:
- [ ] Manager's `init()` references lazy let
- [ ] No compiler errors
- [ ] Registration triggered before any model loading code

**Reference**: SwiftVoxAlta lines 269–272

---

## Phase 3: Download & Loading Integration

**Estimated Duration**: 30 minutes  
**Effort Level**: Medium (existing code modifications)

### 3.1 Call ensureComponentReady() Before Loading

- [ ] Locate your `loadModel()` or equivalent method
- [ ] Before loading from disk, add:
  ```swift
  if let modelRepo = YourModelRepo(rawValue: repo) {
    try await Acervo.ensureComponentReady(modelRepo.componentId)
  }
  ```
- [ ] Ensure this call happens BEFORE model loading
- [ ] Test with at least one model variant
- [ ] Verify no compilation errors

**Success Criteria**:
- [ ] `ensureComponentReady()` called before model loading
- [ ] Component ID passed correctly
- [ ] Compiles without errors
- [ ] Manual test: downloading a model works (first time load)

**Reference**: SwiftVoxAlta lines 340–342

### 3.2 Implement Memory Checking

- [ ] Locate descriptor metadata retrieval:
  ```swift
  if let modelRepo = YourModelRepo(rawValue: repo),
      let descriptor = Acervo.component(modelRepo.componentId) {
    await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
  }
  ```
- [ ] Implement or enhance `checkMemory()` method
- [ ] Add logic to warn if memory insufficient
- [ ] Consider fallback behavior (warn vs. fail)
- [ ] Test with models of different sizes

**Success Criteria**:
- [ ] Memory check retrieves descriptor correctly
- [ ] Descriptor's `minimumMemoryBytes` used (not hardcoded)
- [ ] Compiles without errors
- [ ] Manual test: memory warning appears when appropriate

**Reference**: SwiftVoxAlta lines 332–336

### 3.3 Implement Error Conversion

- [ ] Locate your model loading error handling
- [ ] Add catch block for `AcervoError`:
  ```swift
  do {
    try await Acervo.ensureComponentReady(componentId)
    // ... continue loading
  } catch let error as AcervoError {
    throw YourError.modelNotAvailable("message: \(error)")
  }
  ```
- [ ] Verify error conversion maintains context
- [ ] Test error paths (download failure, missing files, etc.)

**Success Criteria**:
- [ ] `AcervoError` caught and converted to library error
- [ ] Error message is user-friendly
- [ ] Compiles without errors
- [ ] Manual test: error handling works correctly

**Reference**: SwiftVoxAlta lines 345–352

### 3.4 Add Legacy Path Migration (Optional)

- [ ] Check if you have legacy model paths (e.g., `~/Library/Caches/`)
- [ ] If yes, implement migration:
  ```swift
  private func migrateIfNeeded() {
    Acervo.migrateFromLegacyPaths(
      from: oldPath,
      to: "intrusive-memory_YourLibrary"
    )
  }
  ```
- [ ] Call migration on first load
- [ ] Verify old models are found in new location

**Success Criteria**:
- [ ] Migration implemented (if applicable)
- [ ] Old model paths work transparently
- [ ] New models go to shared directory
- [ ] No data loss

**Reference**: SwiftVoxAlta line 318

---

## Phase 4: Testing

**Estimated Duration**: 45 minutes  
**Effort Level**: Medium (new tests, straightforward)

### 4.1 Unit Test - Registration

- [ ] Create `YourLibraryComponentTests.swift`
- [ ] Write test: verify all models registered
  ```swift
  func testAllModelsRegistered() {
    let manager = YourManager()
    for model in YourModelRepo.allCases {
      XCTAssertNotNil(Acervo.component(model.componentId))
    }
  }
  ```
- [ ] Write test: verify descriptor metadata
  ```swift
  func testDescriptorMetadata() {
    let manager = YourManager()
    for model in YourModelRepo.allCases {
      let desc = Acervo.component(model.componentId)!
      XCTAssertEqual(desc.displayName, model.displayName)
      XCTAssertGreater(desc.minimumMemoryBytes, 0)
    }
  }
  ```
- [ ] Run tests locally: `make test-unit`
- [ ] Verify all pass

**Success Criteria**:
- [ ] Both unit tests written
- [ ] Tests pass locally
- [ ] All models iterated via `allCases`
- [ ] Coverage: registration, display name, memory bytes

**Reference**: SwiftVoxAlta CDNAvailabilityTests.swift

### 4.2 Unit Test - File Declarations

- [ ] Write test: verify file count
  ```swift
  func testRequiredFilesCount() {
    let manager = YourManager()
    let expectedCount = 12  // or your number
    for model in YourModelRepo.allCases {
      let desc = Acervo.component(model.componentId)!
      XCTAssertEqual(desc.files.count, expectedCount)
    }
  }
  ```
- [ ] Write test: verify each file has valid path
  ```swift
  func testFilePathsValid() {
    let manager = YourManager()
    for model in YourModelRepo.allCases {
      let desc = Acervo.component(model.componentId)!
      for file in desc.files {
        XCTAssertFalse(file.relativePath.isEmpty)
        XCTAssertFalse(file.relativePath.contains(".."))
      }
    }
  }
  ```
- [ ] Run tests: `make test-unit`
- [ ] Verify all pass

**Success Criteria**:
- [ ] File count test passes for all models
- [ ] File path validation passes
- [ ] All tests run without errors

### 4.3 Integration Test - Download & Load

- [ ] Write integration test for smallest model:
  ```swift
  func testSmallModelDownloadAndLoad() async throws {
    let manager = YourManager()
    let repo = YourModelRepo.modelSmall.rawValue
    let model = try await manager.loadModel(repo: repo)
    XCTAssertNotNil(model)
  }
  ```
- [ ] Run test: `make test` (full suite)
- [ ] Monitor: first time should download, second should use cache
- [ ] Verify success
- [ ] Optional: test larger model (slower but thorough)

**Success Criteria**:
- [ ] Integration test written
- [ ] Test passes (download + load works)
- [ ] Manual verification: files cached in ~/Library/SharedModels/
- [ ] Second run uses cache (faster)

**Reference**: SwiftVoxAlta doesn't have download tests (CDN cost), but pattern shown above

### 4.4 Error Handling Tests

- [ ] Write test: invalid model ID
  ```swift
  func testInvalidModelError() async {
    let manager = YourManager()
    do {
      _ = try await manager.loadModel(repo: "invalid/repo")
      XCTFail("Should throw error")
    } catch {
      XCTAssertTrue(error is YourError)
    }
  }
  ```
- [ ] Run tests: `make test`
- [ ] Verify error handling is correct

**Success Criteria**:
- [ ] Error handling tests written
- [ ] Tests pass
- [ ] Errors are library-specific (not AcervoError)

---

## Phase 5: Documentation

**Estimated Duration**: 15 minutes  
**Effort Level**: Low (documentation only)

### 5.1 Update README

- [ ] Open your library's README.md
- [ ] Add section: "Model Registration" or "Supported Models"
- [ ] List all supported models with:
  - Display name
  - Size requirements
  - Memory requirements
  - Use cases (lightweight vs. high-quality)
- [ ] Link to adoption template:
  ```markdown
  For implementation details, see the 
  [ComponentDescriptor Adoption Template](../docs/COMPONENTDESCRIPTOR_ADOPTION_TEMPLATE.md).
  ```

**Success Criteria**:
- [ ] README updated with model list
- [ ] Memory requirements documented
- [ ] Link to adoption guide included
- [ ] Markdown formatting valid

### 5.2 Create AGENTS.md Section (or Update)

- [ ] Check if AGENTS.md exists
- [ ] Add section: "Model Management"
- [ ] Document:
  - How models are discovered (enumeration)
  - How to load a specific model
  - How memory is managed
  - How deprecated models are handled
- [ ] Example code:
  ```swift
  // Load the Base 1.7B model
  let model = try await manager.loadModel(
    repo: YourModelRepo.base1_7B.rawValue
  )
  ```

**Success Criteria**:
- [ ] AGENTS.md section added (or created if missing)
- [ ] Model management documented
- [ ] Code examples provided
- [ ] Markdown valid

**Reference**: SwiftVoxAlta AGENTS.md (30KB document)

### 5.3 Update CHANGELOG

- [ ] Open CHANGELOG.md
- [ ] Add entry under "Unreleased" or new version:
  ```markdown
  ## [Unreleased]

  ### Added
  - ComponentDescriptor registration for all model variants
  - Atomic model downloads via SwiftAcervo
  - Cross-library model sharing
  - Memory validation before model loading
  ```

**Success Criteria**:
- [ ] CHANGELOG updated
- [ ] Entry describes ComponentDescriptor addition
- [ ] Markdown formatting valid

### 5.4 Document Deprecation (if applicable)

- [ ] If you have deprecated models, add section:
  ```markdown
  ## Deprecated Models

  The following models are deprecated and will be removed in v2.0:

  - **YourModel Legacy**: Use YourModel Small instead

  Existing cached models will continue to work, but new downloads 
  are not recommended. To remove: delete from ~/Library/SharedModels/
  ```
- [ ] Create migration guide if needed

**Success Criteria**:
- [ ] Deprecation documented (if applicable)
- [ ] Migration path clear
- [ ] Timeline specified (e.g., "v2.0")

---

## Phase Completion Summary

| Phase | Duration | Effort | Complexity | Dependencies |
|-------|----------|--------|-----------|---|
| 1: Planning | 30 min | Low | Analysis | None |
| 2: Code | 1 hour | Medium | Copy pattern | Phase 1 complete |
| 3: Integration | 30 min | Medium | Modify existing | Phase 2 complete |
| 4: Testing | 45 min | Medium | Write tests | Phase 3 complete |
| 5: Documentation | 15 min | Low | Writing | All phases complete |

**Total**: ~2.75 hours (170 minutes)

---

## Success Criteria Checklist

Before marking implementation as complete:

### Phase 1 ✓
- [ ] All model variants identified (≥2)
- [ ] File requirements documented (≥8 files)
- [ ] Memory calculations complete (size × headroom)
- [ ] Deprecation plan documented (if applicable)

### Phase 2 ✓
- [ ] Enumeration with `CaseIterable` + `Sendable`
- [ ] Component ID mapping defined
- [ ] 7+ ComponentDescriptor instances created
- [ ] Lazy initializer implemented
- [ ] Manager init triggers registration

### Phase 3 ✓
- [ ] `ensureComponentReady()` called before loading
- [ ] Memory check uses descriptor metadata
- [ ] Error conversion to library-specific error
- [ ] Legacy path migration (if applicable)
- [ ] Manual test: loading works

### Phase 4 ✓
- [ ] Registration unit tests pass
- [ ] File declaration tests pass
- [ ] Integration test (download + load) passes
- [ ] Error handling tests pass
- [ ] All tests run: `make test`

### Phase 5 ✓
- [ ] README updated with model list
- [ ] AGENTS.md section added
- [ ] CHANGELOG entry written
- [ ] Deprecation documented (if applicable)
- [ ] All documentation markdown valid

---

## Common Blockers & Solutions

### Blocker: "Acervo not found in project"

**Solution**: Ensure SwiftAcervo is a dependency in Package.swift:

```swift
.package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", from: "1.0.0")
```

### Blocker: "ComponentDescriptor init unknown"

**Solution**: Check SwiftAcervo version. Constructor may differ. Reference current VoxAlta implementation:

```bash
cd /Users/stovak/Projects/SwiftVoxAlta
grep "ComponentDescriptor(" Sources/SwiftVoxAlta/*.swift
```

### Blocker: "Memory values too high/low"

**Solution**: Use actual observed values. For debugging:

```swift
let actualSize = try FileManager.default
  .attributesOfItem(atPath: modelPath)["NSFileSize"] as! Int
print("Actual model size: \(actualSize / 1_000_000_000) GB")
```

### Blocker: "Models download to wrong location"

**Solution**: Verify SwiftAcervo configuration:

```swift
let modelPath = Acervo.modelPath(for: "your-model-id")
print("Model path: \(modelPath)")  // Should be ~/Library/SharedModels/
```

---

## How to Use This Checklist

1. **Print this document** or keep it open in a split window
2. **Work through each phase** sequentially
3. **Check off each item** as you complete it
4. **Document blockers** or deviations
5. **Review completion summary** before submitting PR
6. **Link to this checklist** in your PR description

---

## Estimated Timeline

- **Day 1 Morning**: Phases 1-2 (1.5 hours)
- **Day 1 Afternoon**: Phase 3 (30 minutes) + Phase 4 initial setup
- **Day 2 Morning**: Phase 4 testing complete (45 minutes)
- **Day 2 Afternoon**: Phase 5 documentation (15 minutes) + PR review

**Total Calendar Time**: 1-2 days (depending on interruptions)

---

**Checklist Version**: 1.0  
**Last Updated**: 2026-04-18  
**Reference Implementation**: SwiftVoxAlta (Sortie 1.1 Complete)
