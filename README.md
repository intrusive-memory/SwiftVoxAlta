<p align="center">
  <img src="swift-vox-alta.jpg" alt="SwiftVoxAlta Logo" width="400">
</p>

# SwiftVoxAlta

A thin VoiceProvider library for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) that provides on-device Qwen3-TTS voice synthesis via [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift).

## Overview

VoxAlta loads voice identities from `.vox` files, resolves clone prompts, and renders speech audio -- all on-device using Apple Silicon. Voice creation (design, clone, character analysis) is handled separately by SwiftEchada (`echada cast`).

### What VoxAlta Provides

- **VoiceProvider implementation** -- text + voiceId -> audio Data (Qwen3-TTS Base model cloning)
- **VoiceProviderDescriptor** -- for auto-registration with SwiftHablare's registry
- **VoxImporter/VoxExporter** -- portable `.vox` voice identity files (container-first API)
- **`diga` CLI** -- drop-in replacement for `/usr/bin/say` with neural text-to-speech

### What VoxAlta Does NOT Provide

- Voice creation/design (SwiftEchada / `echada cast`)
- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Streaming playback (SwiftHablare / app layer)

## Requirements

- macOS 26+ / iOS 26+ (Apple Silicon only)
- Swift 6.2+
- Xcode 26+

### M5 Neural Accelerator Support

SwiftVoxAlta automatically detects and leverages **M5 Neural Accelerators** (Apple M5/M5 Pro/M5 Max/M5 Ultra chips, 2025+) for significant TTS performance improvements:

- **4x faster inference** on macOS 26.2+ with M5 chips
- **Zero code changes required** - MLX auto-detects Neural Accelerators at runtime
- **Automatic fallback** - Works seamlessly on M1/M2/M3/M4 without Neural Accelerators

## Installation

### Homebrew (CLI tool)

```bash
brew tap intrusive-memory/tap
brew install diga
```

### Swift Package Manager (library)

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftVoxAlta.git", from: "0.7.0")
]
```

Then add the library target to your dependency list:

```swift
.product(name: "SwiftVoxAlta", package: "SwiftVoxAlta")
```

## Documentation

- **[diga CLI Reference](docs/CLI.md)** -- CLI usage, voice management, model selection, .vox files
- **[Building & Testing](docs/BUILDING.md)** -- Build from source, Makefile targets, test suites, CI behavior
- **[Migration from v0.2.x](docs/MIGRATION.md)** -- Breaking changes in v0.3.0
- **[Produciesta Integration](docs/PRODUCIESTA_INTEGRATION.md)** -- Voice provider setup for Produciesta
- **[Available Voices](docs/AVAILABLE_VOICES.md)** -- CustomVoice preset speakers

## Produciesta Integration

VoxAlta provides 9 high-quality CustomVoice preset speakers for character voice assignment in Produciesta without any setup required. These voices are production-ready and work seamlessly across iOS and macOS apps.

### Available Voices

**All voices are fully multilingual with English as their primary language.** Voice descriptions reference accent and prosody characteristics rather than exclusive language support.

- **Ryan** -- Dynamic male voice with strong rhythmic drive
- **Aiden** -- Sunny American male voice with clear midrange
- **Vivian** -- Bright, slightly edgy young Chinese female voice (English + Mandarin)
- **Serena** -- Warm, gentle young Chinese female voice (English + Mandarin)
- **Uncle Fu** -- Seasoned Chinese male voice with low, mellow timbre (English + Mandarin)
- **Dylan** -- Youthful Beijing male voice with clear timbre (English + Mandarin)
- **Eric** -- Lively Chengdu male voice with husky brightness (English + Mandarin)
- **Anna** -- Playful Japanese female voice with light timbre (English + Japanese)
- **Sohee** -- Warm Korean female voice with rich emotion (English + Korean)

### Quick Start

```swift
import SwiftVoxAlta

let provider = VoxAltaVoiceProvider()
let audio = try await provider.generateAudio(
    text: "Hello from VoxAlta",
    voiceId: "ryan",
    languageCode: "en"
)
```

For detailed integration instructions, see **[Produciesta Integration Guide](docs/PRODUCIESTA_INTEGRATION.md)**.

## Dependencies

- [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) -- VoiceProvider protocol
- [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) -- Qwen3-TTS inference
- [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) -- Shared model management and caching
- [vox-format](https://github.com/intrusive-memory/vox-format) -- Portable `.vox` voice identity file format

## License

MIT
