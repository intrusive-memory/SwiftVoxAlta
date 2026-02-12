# SwiftVoxAlta

A thin VoiceProvider library for [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) that provides on-device Qwen3-TTS voice design and cloning capabilities via [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift).

## Overview

VoxAlta ingests structured screenplay data from [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido), analyzes characters using [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) (LLM inference), designs voices with Qwen3-TTS VoiceDesign, locks voice identities via clone prompts, and renders dialogue audio -- all on-device using Apple Silicon.

### What VoxAlta Provides

- **VoiceProvider implementation** -- text + voiceId -> audio Data (Qwen3-TTS Base model cloning)
- **Voice design API** -- character evidence -> CharacterProfile -> voice candidates -> locked voice
- **VoiceProviderDescriptor** -- for auto-registration with SwiftHablare's registry
- **`diga` CLI** -- drop-in replacement for `/usr/bin/say` with neural text-to-speech

### What VoxAlta Does NOT Provide

- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Streaming playback (SwiftHablare / app layer)

## Requirements

- macOS 26+ / iOS 26+ (Apple Silicon only)
- Swift 6.2+
- Xcode 26+

## Installation

### Homebrew (CLI tool)

```bash
brew tap intrusive-memory/tap
brew install diga
```

### Swift Package Manager (library)

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftVoxAlta.git", from: "0.1.0")
]
```

Then add the library target to your dependency list:

```swift
.product(name: "SwiftVoxAlta", package: "SwiftVoxAlta")
```

## `diga` CLI

`diga` is a drop-in replacement for macOS `/usr/bin/say` using on-device neural text-to-speech via Qwen3-TTS.

```bash
# Speak text
diga "Hello, world!"

# Read from file or stdin
diga -f input.txt
echo "Hello" | diga

# Write to file (WAV, AIFF, or M4A)
diga -o output.wav "Hello, world!"

# Voice management
diga --voices                                          # List voices
diga -v elena "Hello"                                  # Use a voice
diga --design "warm female voice, 30s, confident" elena  # Design voice
diga --clone reference.wav elena                       # Clone voice

# Model selection
diga --model 0.6b "Hello"   # Smaller model (<16GB RAM)
diga --model 1.7b "Hello"   # Larger model (better quality)
```

On first run, `diga` auto-downloads the appropriate Qwen3-TTS model (~2-4 GB) from HuggingFace.

## Building from Source

**Important**: Use `xcodebuild` or the Makefile. Metal shaders required by Qwen3-TTS won't compile with `swift build`.

```bash
make build      # Development build
make release    # Release build + copy to ./bin
make test       # Run all tests
make install    # Debug build + copy to ./bin
```

## Dependencies

- [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) -- VoiceProvider protocol
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) -- Input types (GuionElementModel, ElementType)
- [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) -- LLM inference for character analysis
- [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) -- Qwen3-TTS inference

## License

MIT
