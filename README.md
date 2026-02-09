# SwiftVoxAlta

A thin VoiceProvider library for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) that provides on-device Qwen3-TTS voice design and cloning capabilities via [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift).

## Overview

VoxAlta ingests structured screenplay data from [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido), analyzes characters using [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) (LLM inference), designs voices with Qwen3-TTS VoiceDesign, locks voice identities via clone prompts, and renders dialogue audio -- all on-device.

### What VoxAlta Provides

- **VoiceProvider implementation** -- text + voiceId -> audio Data (Qwen3-TTS Base model cloning)
- **Voice design API** -- character evidence -> CharacterProfile -> voice candidates -> locked voice
- **VoiceProviderDescriptor** -- for auto-registration with SwiftHablare's registry

### What VoxAlta Does NOT Provide

- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Streaming playback (SwiftHablare / app layer)

## Requirements

- macOS 26+ / iOS 26+
- Swift 6.2+
- Xcode 26+

## Dependencies

- [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) -- VoiceProvider protocol
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) -- Input types (GuionElementModel, ElementType)
- [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) -- LLM inference for character analysis
- [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) -- Qwen3-TTS inference

## License

MIT
