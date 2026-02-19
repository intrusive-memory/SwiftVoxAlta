# Changelog

All notable changes to SwiftVoxAlta will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-02-16

### Added

- **VoxFormat integration** -- Portable `.vox` voice identity files via [vox-format](https://github.com/intrusive-memory/vox-format)
  - `VoxExporter` -- Export voices to `.vox` archives with manifest, reference audio, and embeddings
  - `VoxImporter` -- Import `.vox` archives and extract voice identity data
  - Clone prompt embedding at `qwen3-tts/clone-prompt.bin`
  - Sample audio embedding at `qwen3-tts/sample-audio.wav`
  - `--import-vox` CLI flag for importing `.vox` files into the voice store
  - Direct `.vox` synthesis via `-v voice.vox` without import
- **Sample audio generation** -- Voice creation (`--design`, `--clone`) now synthesizes a phoneme pangram, plays it through speakers, and embeds it into the `.vox` file
- **GenerationContext envelope** -- New `GenerationContext` struct wraps phrase text for TTS generation, replacing raw string passing through `VoiceLockManager`
- **Phoneme pangram constant** -- `VoiceDesigner.phonemePangram` covers all English phonemes for representative voice samples
- **AudioConversion NaN guard** -- Prevents crashes on malformed audio data with non-finite float samples

### Changed

- `VoiceLockManager.generateAudio` now accepts `GenerationContext` instead of raw `String`
- `runDesignVoice` and `runCloneVoice` are now async, generating clone prompt + sample audio after `.vox` creation
- `DigaEngine.loadOrCreateClonePrompt` promoted from private to internal visibility
- VoxFormat dependency switched from local path to GitHub URL

### Fixed

- xcodebuild destination in Makefile test targets now includes `arch=arm64` (was missing in `test-unit` and `test-integration`)

---

## [0.4.0] - 2026-02-16

### Changed

- **Breaking**: Removed Git LFS models from the repository
- Models now downloaded at runtime via SwiftAcervo to `~/Library/SharedModels/`
- No Git LFS installation required

### Added

- CI HuggingFace model caching with symlinks to SharedModels directory
- Release workflow permissions for uploading binary assets

### Removed

- `Models/` directory and all Git LFS tracking

---

## [0.3.0] - 2026-02-15

### Added

- **VoiceDesign character voice pipeline** -- Complete workflow from CharacterProfile to locked voice identity
  - `VoiceDesigner.generateCandidates()` -- Parallel voice candidate generation via TaskGroup
  - `VoiceDesigner.composeVoiceDescription()` -- Profile to TTS description composition
  - `VoiceLockManager.createLock()` -- Clone prompt extraction from candidate audio
  - `VoiceLockManager.generateAudio()` -- Dialogue synthesis from locked voice
- **AppleSiliconInfo** -- M5 Neural Accelerator detection (M1-M5 generation detection)
- **Clone prompt caching** -- 2x speedup on repeated audio generation
- **VoiceDesign integration tests** -- Full pipeline validation (profile -> audio)

### Changed

- Performance: Parallel candidate generation (1.7-3x speedup), clone prompt caching (2x), M5 Neural Accelerators (4x on macOS 26.2+)

---

## [0.2.1] - 2026-02-14

### Changed

- Documented multilingual capabilities of all 9 preset speakers
- Fixed VoxAlta provider configuration for CLI integration
- `fetchVoices(languageCode:)` returns all voices regardless of language parameter

---

## [0.2.0] - 2026-02-14

### Added

- **CustomVoice preset speakers** -- 9 production-ready voices (Ryan, Aiden, Vivian, Serena, Uncle Fu, Dylan, Eric, Anna, Sohee)
- **SwiftAcervo integration** -- Shared model management at `~/Library/SharedModels/`
- **Dual-mode voice routing** -- Preset speakers (Route 1) and clone prompts (Route 2)
- Binary integration tests for diga CLI
- VoiceProvider pipeline integration tests

### Changed

- Replaced local model management with SwiftAcervo
- Automatic migration from legacy cache paths

---

## [0.1.0] - 2026-02-12

### Added

- **SwiftVoxAlta library** -- VoiceProvider implementation for SwiftHablare using Qwen3-TTS
  - Voice design pipeline: character evidence -> CharacterProfile -> voice candidates -> locked voice
  - Voice cloning from reference audio (Base model)
  - Voice design from text descriptions (VoiceDesign model)
  - VoiceProviderDescriptor auto-registration for SwiftHablare
  - Model manager with memory validation and HuggingFace downloads
- **`diga` CLI** -- Drop-in replacement for `/usr/bin/say` with neural TTS
  - Voice store for managing custom and cloned voices
  - Audio playback and file output (WAV, AIFF, M4A)
  - Model management with auto-download
  - Apple TTS `say` fallback
