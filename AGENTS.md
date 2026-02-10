# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftVoxAlta codebase.

**Current Version**: Development (February 2026)

---

## Project Overview

SwiftVoxAlta is a VoiceProvider library for SwiftHablare that provides on-device voice design and cloning capabilities using Qwen3-TTS via mlx-audio-swift.

**Purpose**: Analyze screenplay characters, design custom voices, lock voice identities through cloning, and render dialogue audio - all on-device using Apple Silicon.

## What VoxAlta Provides

- **VoiceProvider implementation** - text + voiceId → audio Data (Qwen3-TTS base model cloning)
- **Voice design API** - character evidence → CharacterProfile → voice candidates → locked voice
- **VoiceProviderDescriptor** - auto-registration with SwiftHablare's provider registry
- **CLI tool (`diga`)** - command-line interface for voice design and audio generation

## What VoxAlta Does NOT Provide

❌ **Fountain parsing** - handled by SwiftCompartido
❌ **Voice selection UI** - handled by app layer
❌ **Audio storage/persistence** - handled by Produciesta / SwiftData
❌ **Streaming playback** - handled by SwiftHablare / app layer

## Project Structure

```
SwiftVoxAlta/
├── Sources/
│   ├── SwiftVoxAlta/          # Library target
│   │   ├── VoiceProvider/     # VoiceProvider protocol implementation
│   │   ├── VoiceDesign/       # Character analysis and voice design
│   │   ├── CharacterProfile/  # Character evidence and profile types
│   │   └── Types/             # Shared types and descriptors
│   └── diga/                  # CLI executable target
└── Tests/
    └── SwiftVoxAltaTests/
```

## Key Components

| Component | Purpose |
|-----------|---------|
| **VoiceProvider** | Implements SwiftHablare's VoiceProvider protocol for Qwen3-TTS |
| **VoiceDesigner** | Analyzes character evidence and generates voice candidates |
| **CharacterProfile** | Structured representation of character attributes |
| **VoiceCandidate** | Generated voice design with prompt and parameters |
| **VoiceProviderDescriptor** | Registration metadata for SwiftHablare |
| **`diga` CLI** | Command-line tool for voice design and synthesis |

## Dependencies

| Package | Purpose |
|---------|---------|
| SwiftHablare | VoiceProvider protocol and registry |
| SwiftCompartido | Input types (GuionElementModel, ElementType) |
| SwiftBruja | LLM inference for character analysis |
| mlx-audio-swift | Qwen3-TTS inference engine |
| swift-argument-parser | CLI argument parsing |

## Voice Design Pipeline

1. **Character Evidence Collection** - Extract dialogue and action lines from screenplay elements
2. **LLM Analysis** - Use SwiftBruja to analyze character traits, age, gender, personality
3. **Profile Creation** - Structure character attributes into CharacterProfile
4. **Voice Candidate Generation** - Generate clone prompts based on character profile
5. **Voice Locking** - Select candidate and lock voice identity for consistent rendering
6. **Audio Synthesis** - Render dialogue using Qwen3-TTS base model with clone prompt

## Build and Test

**CRITICAL**: Use `xcodebuild` for all builds and tests. Qwen3-TTS requires Metal shaders which don't compile with `swift build`.

```bash
# Build library
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS'

# Run tests
xcodebuild test -scheme SwiftVoxAlta -destination 'platform=macOS'

# Build CLI tool
xcodebuild build -scheme diga -destination 'platform=macOS'
```

## Platform Requirements

- **macOS 26.0+** (Apple Silicon only for Qwen3-TTS)
- **iOS 26.0+** (Apple Silicon only)
- **Swift 6.2+**
- **Xcode 17+**

## API Usage

### VoiceProvider Implementation

```swift
import SwiftVoxAlta
import SwiftHablare

// Get VoxAlta provider
let provider = VoxAltaVoiceProvider()

// Generate audio
let audioData = try await provider.speak(
    text: "Hello from VoxAlta!",
    voiceId: "character-voice-id"
)
```

### Voice Design API

```swift
import SwiftVoxAlta

// Collect character evidence from screenplay
let evidence = CharacterEvidence(
    dialogue: [...],
    actions: [...],
    sceneContexts: [...]
)

// Analyze and create profile
let profile = try await VoiceDesigner.analyzeCharacter(evidence: evidence)

// Generate voice candidates
let candidates = try await VoiceDesigner.generateCandidates(profile: profile)

// Lock voice identity
let lockedVoice = try await VoiceDesigner.lockVoice(candidate: candidates[0])
```

### CLI Tool (`diga`)

```bash
# Design voice from screenplay
diga design --screenplay episode-01.fountain --character "JOHN DOE"

# Generate audio
diga speak --text "Hello world" --voice character-voice-id

# List available voices
diga list
```

## Design Patterns

- **VoiceProvider abstraction** - Implements SwiftHablare's protocol for plug-and-play integration
- **Character-driven voice design** - Analyzes character evidence to generate appropriate voices
- **Clone prompt locking** - Ensures voice consistency across all character dialogue
- **On-device inference** - All LLM and TTS processing runs locally via Apple Silicon GPU
- **Lazy voice loading** - Qwen3-TTS models loaded on-demand to conserve memory
- **Strict concurrency** - Swift 6 language mode with actor isolation

## Integration with SwiftHablare

VoxAlta auto-registers with SwiftHablare's provider registry:

```swift
// In app initialization
import SwiftHablare
import SwiftVoxAlta

// VoxAlta automatically registers via VoiceProviderDescriptor
let service = GenerationService()

// VoxAlta provider now available
let provider = try service.provider(for: "voxalta://")
```

## CLI Commands

| Command | Purpose | Key Flags |
|---------|---------|-----------|
| `design` | Analyze character and generate voice | `--screenplay`, `--character`, `--output` |
| `speak` | Generate audio from text | `--text`, `--voice`, `--output` |
| `list` | List available voices | (none) |
| `analyze` | Show character profile without voice generation | `--screenplay`, `--character` |

## Voice Identity Format

VoxAlta uses a structured voiceId format:

```
voxalta://<character-name>/<clone-prompt-hash>
```

Example: `voxalta://john-doe/a1b2c3d4`

This ensures:
- Unique voice identity per character
- Deterministic voice selection based on locked clone prompt
- Compatibility with SwiftHablare's URI-based provider routing

## Memory Management

- **Model caching** - Qwen3-TTS models cached in `~/Library/Caches/intrusive-memory/Models/Audio/`
- **Lazy loading** - Models loaded only when needed for synthesis
- **Memory validation** - Pre-load checks ensure sufficient memory (similar to SwiftBruja)
- **Automatic cleanup** - Models released when memory pressure detected

## Development Workflow

- **Branch**: `development` → PR → `main`
- **CI Required**: Tests must pass before merge
- **Never commit directly to `main`**
- **Platforms**: macOS 26+, iOS 26+ only (Apple Silicon required)
- **NEVER add `@available` attributes** for older platforms

## Testing Strategy

- **Unit tests** - VoiceProvider implementation, profile creation
- **Integration tests** - End-to-end voice design pipeline
- **Voice quality tests** - Character-appropriate voice generation
- **Performance tests** - Audio synthesis latency and throughput

## Error Handling

| Error | When |
|-------|------|
| `VoxAltaError.characterNotFound` | Character name not found in screenplay |
| `VoxAltaError.insufficientEvidence` | Not enough dialogue/action lines for analysis |
| `VoxAltaError.voiceGenerationFailed` | Qwen3-TTS synthesis failed |
| `VoxAltaError.profileCreationFailed` | LLM character analysis failed |
| `VoxAltaError.invalidVoiceId` | VoiceId format incorrect or not found |

## Future Enhancements

- **Voice fine-tuning** - Train Qwen3-TTS LoRA adapters for locked voices
- **Emotion control** - Vary prosody based on scene context
- **Multi-language support** - Extend voice design to non-English characters
- **Voice mixing** - Blend multiple clone prompts for unique voices
- **Streaming synthesis** - Real-time audio generation for long dialogue

## Important Notes

- **Apple Silicon required** - Qwen3-TTS via MLX requires M1/M2/M3/M4 GPU
- **Model downloads** - First use auto-downloads Qwen3-TTS (~2-4 GB)
- **Character consistency** - Locked voices ensure same character sounds identical across scenes
- **Privacy** - All processing on-device, no cloud APIs
- **Experimental status** - VoxAlta is in active development, APIs may change
