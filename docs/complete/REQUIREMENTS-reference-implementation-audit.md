# SwiftVoxAlta Acervo Integration Requirements

**Status**: ✅ **COMPLETE** — Reference Implementation  
**Date**: 2026-04-18  
**Audit**: See [ACERVO_CONSUMER_AUDIT.md](/Users/stovak/Projects/ACERVO_CONSUMER_AUDIT.md) (lines 117–134)

---

## Overview

SwiftVoxAlta is the **reference implementation** for SwiftAcervo v2 integration. This project demonstrates the ideal pattern for consuming libraries and requires **no changes**.

Detailed compliance documentation is archived at `docs/complete/REQUIREMENTS_REFERENCE.md` for reference by other teams implementing similar patterns.

---

## What Makes SwiftVoxAlta Compliant

### ✅ Component Registration (7 Variants)

All TTS model variants are registered via `ComponentDescriptor` at module initialization:

```
qwen3-tts-base-0.6b          (600 MB)
qwen3-tts-base-1.7b          (3.4 GB) ← primary
qwen3-tts-custom-voice-0.6b  (600 MB)
qwen3-tts-custom-voice-1.7b  (3.4 GB)
qwen3-tts-voice-design-0.6b  (600 MB)
qwen3-tts-voice-design-1.7b  (3.4 GB)
(deprecated: 4-bit variant)
```

**Location**: `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`

### ✅ API Pattern

- **ensureComponentReady()** — Type-safe component download with file-level progress
- **Scoped file access** — Model loading delegated to specialized loaders (TTSModelUtils)
- **High-level API** — Public synthesize/listVoices methods; no leaked file paths
- **Error conversion** — AcervoError → VoxAltaError with context-specific messages

### ✅ Integrity & Verification

- **SHA-256 checksums** declared for all files in ComponentDescriptor
- **Manifest validation** via SwiftAcervo before download begins
- **Memory requirements** specified per variant for GPU planning
- **Atomic downloads** — model fully available before use

### ✅ Documentation

- **AGENTS.md** — Model variants, memory requirements, error recovery
- **README.md** — Default selection, storage location, first-run behavior
- **Unit tests** — Descriptor registration and download flow
- **Integration tests** — Full cycle with audio quality verification

---

## For Other Teams

If you're implementing SwiftAcervo v2 in another library:

1. **Study this reference**: `docs/complete/REQUIREMENTS_REFERENCE.md` (187 lines with patterns and code examples)
2. **Follow the checklist**: Items 1–13 in the compliance section are applicable to all consumers
3. **Adapt the model list**: Your library will have different components; the pattern is universal

---

## Master Reference

For shared patterns across all SwiftAcervo consumers, integration policy decisions, and ModelDownloadManager orchestration, see:

📘 **[ACERVO_INTEGRATION_REQUIREMENTS.md](/Users/stovak/Projects/ACERVO_INTEGRATION_REQUIREMENTS.md)** (master reference)

---

## Status Summary

| Aspect | Status |
|--------|--------|
| Component Registration | ✅ Excellent (7 variants, full checksums) |
| API Integration | ✅ Complete (ensureComponentReady + high-level API) |
| File Access Pattern | ✅ Compliant (scoped, delegated loaders) |
| Integrity Verification | ✅ Complete (SHA-256, manifest validation) |
| Documentation | ✅ Complete (AGENTS.md, README, tests) |
| Error Handling | ✅ Complete (typed errors with context) |

**Conclusion**: No changes required. This is the ideal pattern for SwiftAcervo v2 consumption.
