# SwiftVoxAlta Acervo Integration Requirements

**Date**: 2026-04-17  
**Status**: ✅ COMPLIANT — Reference Implementation  
**Pattern**: ComponentDescriptor + ensureComponentReady() (Pattern B from master reference)

---

## Overview

SwiftVoxAlta fully implements the ComponentDescriptor registration pattern for managing 7 TTS (text-to-speech) model variants via SwiftAcervo. This is the **ideal reference implementation** for consuming libraries.

**No changes required** — this document records the current compliant state.

---

## Models

SwiftVoxAlta manages 7 TTS variants registered at module initialization:

| Component ID | Model | Size | Type |
|---|---|---|---|
| `qwen3-tts-base-0.6b` | Qwen3-TTS 0.6B Base | ~600 MB | Base model |
| `qwen3-tts-base-1.7b` | Qwen3-TTS 1.7B Base | ~3.4 GB | Base model (primary) |
| `qwen3-tts-custom-voice-0.6b` | Qwen3-TTS 0.6B CustomVoice | ~600 MB | Custom voice extension |
| `qwen3-tts-custom-voice-1.7b` | Qwen3-TTS 1.7B CustomVoice | ~3.4 GB | Custom voice extension |
| `qwen3-tts-voice-design-0.6b` | Qwen3-TTS 0.6B VoiceDesign | ~600 MB | Voice design extension |
| `qwen3-tts-voice-design-1.7b` | Qwen3-TTS 1.7B VoiceDesign | ~3.4 GB | Voice design extension |
| (deprecated) | Qwen3-TTS 4-bit | ~2.0 GB | Deprecated (kept for backward compat) |

---

## Current Pattern (IDEAL — No Changes Required)

### 1. ComponentDescriptor Registration at Module Init

**Location**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

```swift
private let _registerQwen3TTSComponents = {
    let descriptors = [
        ComponentDescriptor(
            id: "qwen3-tts-base-1.7b",
            type: .languageModel,
            displayName: "Qwen3-TTS Base 1.7B (bf16)",
            repoId: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
            files: [
                "config.json",
                "model.safetensors",
                "tokenizer.json",
                // ... 12 files total
            ],
            estimatedSizeBytes: 3_400_000_000,
            minimumMemoryBytes: 3_400_000_000
        ),
        // ... 6 more descriptors
    ]
    Acervo.register(descriptors)
}()
```

**Key Characteristics**:
- ✅ Files declared upfront (no dynamic discovery)
- ✅ Manifest validation happens before download
- ✅ Memory requirements specified
- ✅ All 12 required files per model listed explicitly

### 2. Download via ensureComponentReady()

**Location**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` in `loadModel(repo:)`

```swift
try await Acervo.ensureComponentReady(modelRepo.componentId) { progress in
    // Structured progress with fileIndex, totalFiles, fileName
    print("[\(progress.component)] \(progress.fileIndex)/\(progress.totalFiles): \(progress.fileName)")
}
```

**Benefits**:
- ✅ Type-safe: uses registered component ID
- ✅ Progress callback includes file-level details
- ✅ Error handling uses typed AcervoError
- ✅ Atomic: model fully downloaded before use

### 3. Scoped File Access

**Location**: Weight loading delegates to model-specific loaders (TTSModelUtils)

```swift
// Path access is not leaked — delegated to specialized loaders
let model = try await TTSModelUtils.loadModel(modelRepo: repo)
```

- ✅ No direct file path exposure
- ✅ Model loading logic encapsulated
- ✅ Easy to replace underlying loaders without changing VoxAltaModelManager

---

## Compliance Checklist

All items complete. This section documents the current state.

- [x] ComponentDescriptors registered at module init (lazy initializer pattern)
- [x] All required files declared per descriptor (12 files per model)
- [x] ensureComponentReady() used for all model downloads
- [x] Memory requirements declared for GPU planning
- [x] Structured progress callbacks with file details
- [x] SHA-256 verification via SwiftAcervo manifest
- [x] Error handling converts AcervoError to library-specific errors
- [x] AGENTS.md documents model requirements and variant selection
- [x] Unit tests verify descriptor registration
- [x] Integration tests verify download and loading workflow

---

## Error Handling

Errors from SwiftAcervo are caught and converted to library-specific types:

```swift
// In VoxAltaModelManager
catch let error as AcervoError {
    switch error {
    case .modelNotFound(let modelId):
        throw VoxAltaError.modelNotAvailable("Component '\(modelId)' not found on CDN")
    case .manifestChecksumMismatch(let modelId):
        throw VoxAltaError.downloadFailed("Manifest integrity check failed for '\(modelId)'")
    case .downloadFailed(let reason):
        throw VoxAltaError.downloadFailed("Download failed: \(reason)")
    case .checksumMismatch(let fileName):
        throw VoxAltaError.downloadFailed("File corrupted during download: \(fileName)")
    }
}
```

---

## Documentation

**AGENTS.md Section**: Documents:
- Which models are available
- How to select a model variant
- Memory requirements for each variant
- Progress reporting behavior
- Error recovery steps

**README.md Section**: Documents:
- Default model selection
- How to change models
- Storage location (App Group container)
- First-run download behavior

---

## Testing

**Unit Tests** (`Tests/SwiftVoxAltaTests/AcervoIntegrationTests.swift`):
- Verify descriptors are registered
- Mock Acervo and test download flow
- Test error handling

**Integration Tests** (manual, requires model download):
- Test full download + load cycle
- Verify audio output quality unchanged
- Confirm model sharing with other tools

---

## Future Enhancements (Optional)

If Acervo v0.8+ introduces new features, consider:
- **Custom voice fingerprinting**: Pre-compute voice embeddings per variant
- **Model caching**: Cache metadata locally (24-hour TTL)
- **Progressive download**: Download model segments as needed during synthesis
- **A/B testing variants**: Download multiple variants and compare quality

---

## Reference

See `/Users/stovak/Projects/ACERVO_INTEGRATION_REQUIREMENTS.md` (master reference) for:
- Shared patterns across all consumers
- ModelDownloadManager for multi-model orchestration
- Policy decisions on file access and error handling
- SwiftAcervo/AGENTS.md for complete API reference
