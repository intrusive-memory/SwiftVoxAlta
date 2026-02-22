# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftVoxAlta codebase.

**Current Version**: 0.7.0

---

## Project Overview

SwiftVoxAlta is a VoiceProvider library for SwiftHablare that provides on-device voice synthesis using Qwen3-TTS via mlx-audio-swift.

**Purpose**: Load voice identities from `.vox` files, resolve clone prompts, and render speech audio -- all on-device using Apple Silicon.

**Voice creation** (design, clone, character analysis) is handled by SwiftEchada (`echada cast`). VoxAlta is purely "load a .vox file, get the clone prompt, synthesize speech."

## What VoxAlta Provides

- **VoiceProvider implementation** -- text + voiceId -> audio Data (Qwen3-TTS base model cloning)
- **VoiceProviderDescriptor** -- auto-registration with SwiftHablare's provider registry
- **VoxImporter/VoxExporter** -- import/export `.vox` voice identity files (container-first API)
- **CLI tool (`diga`)** -- drop-in replacement for `/usr/bin/say` with neural TTS

## What VoxAlta Does NOT Provide

- Voice creation/design (SwiftEchada / `echada cast`)
- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Streaming playback (SwiftHablare / app layer)

## Installation

### Homebrew (recommended for CLI)

```bash
brew tap intrusive-memory/tap
brew install diga
```

### Swift Package Manager (for library integration)

```swift
.package(url: "https://github.com/intrusive-memory/SwiftVoxAlta.git", from: "0.7.0")
```

## Project Structure

```
SwiftVoxAlta/
├── Sources/
│   ├── SwiftVoxAlta/                  # Library target
│   │   ├── AppleSiliconInfo.swift     # Apple Silicon generation detection (M1-M5)
│   │   ├── AudioConversion.swift      # WAV format utilities
│   │   ├── GenerationContext.swift    # TTS generation context envelope
│   │   ├── VoiceLock.swift            # Locked voice identity type
│   │   ├── VoiceLockManager.swift     # Audio generation from locked voices
│   │   ├── VoxAltaConfig.swift        # Configuration (model IDs, output format)
│   │   ├── VoxAltaError.swift         # Error types
│   │   ├── VoxAltaModelManager.swift  # Qwen3-TTS model lifecycle (actor)
│   │   ├── VoxAltaProviderDescriptor.swift  # SwiftHablare registration
│   │   ├── VoxAltaVoiceCache.swift    # Thread-safe voice cache (actor)
│   │   ├── VoxAltaVoiceProvider.swift # VoiceProvider protocol implementation
│   │   ├── VoxExporter.swift          # Update clone prompts/sample audio in .vox files
│   │   └── VoxImporter.swift          # Import .vox voice identity files
│   └── diga/                          # CLI executable target
│       ├── AudioFileWriter.swift      # WAV/AIFF/M4A file output
│       ├── AudioPlayback.swift        # Speaker playback via AVAudioPlayer
│       ├── BuiltinVoices.swift        # Built-in voice presets
│       ├── DigaCommand.swift          # CLI entry point and argument parsing
│       ├── DigaEngine.swift           # Synthesis engine (text -> WAV data)
│       ├── DigaModelManager.swift     # Model download and cache management
│       ├── TextChunker.swift          # Split long text for chunked synthesis
│       ├── Version.swift              # Version constant (0.7.0)
│       └── VoiceStore.swift           # Persistent custom voice storage
├── Tests/
│   ├── SwiftVoxAltaTests/             # Library tests
│   └── DigaTests/                     # CLI tests
├── Formula/
│   └── diga.rb                        # Reference Homebrew formula
├── Makefile                           # Build targets (xcodebuild wrapper)
├── Package.swift
├── AGENTS.md                          # This file
├── CHANGELOG.md                       # Release history
├── CLAUDE.md                          # Claude Code-specific instructions
├── GEMINI.md                          # Gemini-specific instructions
└── README.md
```

## Key Components

| Component | Purpose |
|-----------|---------|
| **VoxAltaVoiceProvider** | Implements SwiftHablare's `VoiceProvider` protocol |
| **VoxAltaModelManager** | Actor managing Qwen3-TTS model lifecycle via mlx-audio-swift |
| **VoxAltaVoiceCache** | Actor caching loaded voice clone prompts for performance |
| **VoiceLockManager** | Generates audio from locked voice identities |
| **AppleSiliconInfo** | Apple Silicon generation detection (M1-M5) and Neural Accelerator status |
| **GenerationContext** | TTS generation context envelope (phrase, metadata) |
| **VoxExporter** | Update clone prompts and sample audio in `.vox` archives |
| **VoxImporter** | Import `.vox` archives and extract voice identity data |
| **VoxAltaConfig** | Configuration (model IDs, candidate count, output format) |
| **VoxAltaProviderDescriptor** | Factory for SwiftHablare registry registration |
| **`diga` CLI** | Drop-in `say` replacement with neural TTS |

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) | VoiceProvider protocol and registry |
| [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) | Qwen3-TTS inference engine (MLXAudioTTS) |
| [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) | Shared model management and caching |
| [vox-format](https://github.com/intrusive-memory/vox-format) | Portable `.vox` voice identity file format |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI argument parsing |

### mlx-audio-swift Fork Notes

VoxAlta uses a fork of `mlx-audio-swift` from the intrusive-memory GitHub org:

- **Repository**: `https://github.com/intrusive-memory/mlx-audio-swift.git`
- **Branch**: `development`
- **Rationale**: Fork includes VoiceDesign v1 support (via PR #23 from upstream) and voice cloning with clone prompts.

This fork enables:
- **Voice Cloning**: Reference audio -> clone prompt generation (Base 0.6B/1.7B models)
- **Preset Speakers**: CustomVoice model with 9 built-in speakers

## VoiceLockManager API

`VoiceLockManager` is an enum namespace providing voice lock creation and audio generation from locked voices.

### `createLock(characterName:candidateAudio:designInstruction:modelManager:modelRepo:)`

Create a VoiceLock from candidate audio by extracting a voice clone prompt using the Base model.

```swift
public static func createLock(
    characterName: String,
    candidateAudio: Data,
    designInstruction: String,
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo = .base1_7B
) async throws -> VoiceLock
```

### `generateAudio(context:voiceLock:language:modelManager:modelRepo:cache:)`

Generate speech audio using a locked voice identity.

```swift
public static func generateAudio(
    context: GenerationContext,
    voiceLock: VoiceLock,
    language: String = "en",
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    cache: VoxAltaVoiceCache? = nil
) async throws -> Data
```

**Performance:**
- First generation: ~20-40s per line (includes clone prompt deserialization)
- Subsequent generations: ~10-20s per line (2x speedup via clone prompt caching)

## VoxFormat (.vox) Integration

VoxAlta uses the [vox-format](https://github.com/intrusive-memory/vox-format) library with the container-first API (`VoxFile` class).

### VoxExporter

Update clone prompts and sample audio in existing `.vox` archives:

```swift
// Update clone prompt in existing .vox
try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: promptData)

// Update sample audio in existing .vox
try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: wavData)

// Path helpers
let path = VoxExporter.clonePromptPath(for: .base1_7B)  // "embeddings/qwen3-tts/1.7b/clone-prompt.bin"
let slug = VoxExporter.modelSizeSlug(for: .base0_6B)    // "0.6b"
```

### VoxImporter

Import `.vox` archives:

```swift
let result = try VoxImporter.importVox(from: voxURL)
// result.name, result.description, result.method
// result.clonePromptData (model-aware lookup with fallback)
// result.sampleAudioData
// result.referenceAudio (keyed by filename)
// result.supportedModels (e.g. ["1.7b", "0.6b"])
```

### Embedding Paths

| Path | Purpose |
|------|---------|
| `embeddings/qwen3-tts/{size}/clone-prompt.bin` | Model-specific clone prompt (e.g. `1.7b/`, `0.6b/`) |
| `embeddings/qwen3-tts/sample-audio.wav` | Engine-generated voice sample |

### CLI Usage

```bash
# Import a .vox file
diga --import-vox voice.vox

# Synthesize directly from a .vox file (no import needed)
diga -v voice.vox "Hello, world!"
```

## Clone Prompt Resolution

When synthesizing with an existing voice (`diga "Hello" -v alice`), `DigaEngine.loadOrCreateClonePrompt()` checks four sources in order:

```
1. Memory cache: cachedClonePrompts["alice:1.7b"]  ── HIT? → use
2. Disk cache: alice-1.7b.cloneprompt              ── HIT? → use
3. Legacy disk: alice.cloneprompt (1.7b only)      ── HIT? → use
4. On-demand extraction from .vox:
   Import alice.vox → extract clone prompt          ── HIT? → use
   (no match) → Error: "Use `echada cast` to create a voice"
```

## Synthesis Flow

```
Text → TextChunker.chunk() → ["sentence 1", "sentence 2", ...]

For each chunk:
  VoiceLockManager.generateAudio()
    clone prompt → VoiceClonePrompt.deserialize()
    Qwen3TTSModel.generateWithClonePrompt(text, prompt)
    → MLXArray → mlxArrayToWAVData → WAV segment

WAVConcatenator.concatenate(segments) → final WAV

Output:
  -o file.wav → AudioFileWriter (wav/aiff/m4a)
  (default)   → AudioPlayback (speakers)
```

## Disk Layout

```
~/.diga/voices/
├── index.json                    ← Voice registry (JSON array of StoredVoice)
├── alice-1.7b.cloneprompt        ← Serialized speaker embedding (~5-10KB)
└── alice.vox                     ← Portable container (ZIP)
    ├── manifest.json             │  name, description, provenance
    ├── reference/                │  (optional reference audio)
    └── embeddings/qwen3-tts/
        ├── 1.7b/clone-prompt.bin │  Model-specific clone prompt
        ├── 0.6b/clone-prompt.bin │  (optional second model)
        └── sample-audio.wav      │  Pangram sample for preview

~/Library/SharedModels/           ← Model weights (shared via Acervo)
├── mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16/         (~4.3GB)
├── mlx-community_Qwen3-TTS-12Hz-0.6B-Base-bf16/         (~2.4GB)
└── mlx-community_Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16/  (presets)
```

## Build and Test

**CRITICAL**: Use `xcodebuild` or the Makefile for all builds and tests. Qwen3-TTS requires Metal shaders which don't compile with `swift build`.

### Makefile Targets

```bash
make build      # Development build (xcodebuild debug)
make install    # Debug build + copy binary and Metal bundle to ./bin
make release    # Release build + copy to ./bin
make test       # Run all tests (library + CLI)
make test-unit  # Fast unit tests only (~5-10 seconds)
make resolve    # Resolve SPM dependencies
make clean      # Clean build artifacts
```

### Direct xcodebuild

```bash
# Build library
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS,arch=arm64'

# Run tests
xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS,arch=arm64'

# Build CLI tool
xcodebuild build -scheme diga -destination 'platform=macOS,arch=arm64'
```

## Platform Requirements

- **macOS 26.0+** (Apple Silicon only -- Qwen3-TTS requires Metal/MLX)
- **iOS 26.0+** (Apple Silicon only)
- **Swift 6.2+**
- **Xcode 26+**

## VoiceProvider Implementation

VoxAltaVoiceProvider implements SwiftHablare's VoiceProvider protocol with dual-mode routing for both preset speakers and custom voices:

### Dual-Mode Routing

1. **Route 1 (Preset speakers)** -- Direct CustomVoice model generation, no setup required:
   ```swift
   let audio = try await provider.generateAudio(
       text: "Hello",
       voiceId: "ryan",  // Routes through Route 1
       languageCode: "en"
   )
   ```
   Supports: `ryan`, `aiden`, `vivian`, `serena`, `uncle_fu`, `dylan`, `eric`, `anna`, `sohee`

2. **Route 2 (Clone prompts)** -- For custom voices loaded via `loadVoice()`:
   ```swift
   await provider.loadVoice(id: "ELENA", clonePromptData: lockData, gender: "female")
   let audio = try await provider.generateAudio(
       text: "Hello",
       voiceId: "ELENA",  // Routes through Route 2
       languageCode: "en"
   )
   ```

### Multilingual Voice Support

All 9 preset speakers are fully multilingual with English as their primary language. `fetchVoices(languageCode: "en")` returns all 9 preset speakers.

### API Usage

```swift
import SwiftVoxAlta
import SwiftHablare

// Create provider
let provider = VoxAltaVoiceProvider()

// Fetch available voices (includes 9 presets + any loaded custom voices)
let voices = try await provider.fetchVoices(languageCode: "en")

// Generate audio with preset speaker (Route 1)
let audioData = try await provider.generateAudio(
    text: "Hello from VoxAlta!",
    voiceId: "ryan",
    languageCode: "en"
)

// Load a custom voice for cloning (Route 2)
await provider.loadVoice(id: "ELENA", clonePromptData: lockData, gender: "female")
let customAudio = try await provider.generateAudio(
    text: "Hello from custom Elena!",
    voiceId: "ELENA",
    languageCode: "en"
)

// Register with SwiftHablare
let registry = VoiceProviderRegistry.shared
await registry.register(VoxAltaProviderDescriptor.descriptor())
```

## CLI Tool (`diga`)

`diga` is a drop-in replacement for `/usr/bin/say` with neural text-to-speech via Qwen3-TTS.

**See [Available Voices Documentation](docs/AVAILABLE_VOICES.md)** for a complete list of built-in voices.

### Usage

```bash
# Speak text (plays through speakers)
diga "Hello, world!"

# Read from file
diga -f input.txt

# Read from stdin
echo "Hello" | diga

# Write to file instead of playing
diga -o output.wav "Hello, world!"
diga -o output.m4a "Hello, world!"    # AAC encoding
diga -o output.aiff "Hello, world!"   # AIFF encoding

# Use a specific voice
diga -v elena "Hello, world!"

# List voices
diga --voices
diga -v ?

# Import a voice from .vox file
diga --import-vox voice.vox

# Override model selection
diga --model 0.6b "Hello"     # Use smaller model
diga --model 1.7b "Hello"     # Use larger model
```

### CLI Flags

| Flag | Short | Purpose |
|------|-------|---------|
| `--voices` | | List all available voices |
| `--voice <name>` | `-v` | Select voice for synthesis |
| `--import-vox <file>` | | Import voice from a `.vox` file |
| `--output <path>` | `-o` | Write to file (WAV/AIFF/M4A) |
| `--file <path>` | `-f` | Read input from file (`-` for stdin) |
| `--file-format <fmt>` | | Override output format (wav, aiff, m4a) |
| `--model <id>` | | Override model (0.6b, 1.7b, or HF repo) |
| `--version` | | Show version |
| `--help` | `-h` | Show help |

To create custom voices, use `echada cast` (from SwiftEchada), then import with `diga --import-vox`.

## Qwen3-TTS Models

| Model | Repo ID | Size | Use Case |
|-------|---------|------|----------|
| Base 1.7B | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` | ~4.3 GB | Voice cloning (recommended) |
| Base 0.6B | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` | ~2.4 GB | Voice cloning (lighter, <16GB RAM) |

- Models are auto-downloaded on first use from HuggingFace
- Cached at `~/Library/SharedModels/` (via SwiftAcervo), shared across the intrusive-memory ecosystem
- `diga` auto-selects 1.7B (>=16GB RAM) or 0.6B (<16GB RAM)

## Error Types

```swift
public enum VoxAltaError: Error {
    case cloningFailed(String)               // Voice cloning from reference audio failed
    case modelNotAvailable(String)           // TTS model not available or download failed
    case voiceNotLoaded(String)              // Voice not in cache (call loadVoice first)
    case insufficientMemory(available:required:) // Not enough RAM for model
    case audioExportFailed(String)           // Audio format conversion failed
    case voxExportFailed(String)             // .vox archive export failed
    case voxImportFailed(String)             // .vox archive import failed
}
```

## Apple Silicon Detection API

`AppleSiliconInfo` provides runtime detection of Apple Silicon generation (M1 through M5) to identify Neural Accelerator availability for MLX performance optimizations.

```swift
import SwiftVoxAlta

let generation = AppleSiliconGeneration.current
print("Running on \(generation.rawValue)")

if generation.hasNeuralAccelerators {
    print("Neural Accelerators available - expect 4x TTS speedup on macOS 26.2+")
}
```

## Design Patterns

- **VoiceProvider abstraction** -- Implements SwiftHablare's protocol for plug-and-play integration
- **Actor isolation** -- `VoxAltaModelManager` and `VoxAltaVoiceCache` are actors for thread safety
- **Lazy model loading** -- Qwen3-TTS models loaded on-demand, cached for reuse, auto-unloaded on switch
- **Memory-aware loading** -- Warns on low memory but lets macOS manage swap (non-blocking)
- **Clone prompt locking** -- `VoiceLock` ensures voice consistency across all character dialogue
- **Container-first .vox API** -- Uses `VoxFile(contentsOf:)` + `add()` + `write(to:)` for all .vox operations
- **On-device inference** -- All TTS processing runs locally via Apple Silicon GPU
- **Strict concurrency** -- Swift 6 language mode with `StrictConcurrency` enabled

## Development Workflow

- **Branch**: `development` -> PR -> `main`
- **CI Required**: Build + tests must pass before merge
- **Never commit directly to `main`**
- **Platforms**: macOS 26+, iOS 26+ only (Apple Silicon required)
- **NEVER add `@available` attributes** for older platforms
- **CI runner**: `macos-26`

## Release Process

1. Tag on `main` (e.g., `v0.7.0`)
2. GitHub Release triggers `.github/workflows/release.yml`
3. Release workflow: `make release` -> tarball -> upload assets -> dispatch to `intrusive-memory/homebrew-tap`
4. Homebrew tap auto-updates formula with new URL and SHA256

## Testing

- **Library tests** (`SwiftVoxAltaTests/`): VoiceProvider, model manager, voice cache, error paths, audio conversion, voice lock, VoxImporter/VoxExporter, Acervo integration
- **CLI tests** (`DigaTests/`): CLI integration, audio file writer, audio playback, engine, model manager, voice store, version, release checks
- **175 tests** across 39 suites (library + CLI)

## Important Notes

- **Apple Silicon required** -- Qwen3-TTS via MLX requires M1/M2/M3/M4 GPU
- **Metal shaders required** -- Must build with `xcodebuild` (not `swift build`)
- **Model downloads** -- First use auto-downloads Qwen3-TTS (~2-4 GB per model)
- **Character consistency** -- Locked voices ensure same character sounds identical across scenes
- **Privacy** -- All processing on-device, no cloud APIs
- **Voice creation** -- Use `echada cast` (SwiftEchada) to design/clone voices, then import with `--import-vox`

## Documentation Index

| Document | Purpose |
|----------|---------|
| [AGENTS.md](AGENTS.md) | This file - complete project documentation |
| [CHANGELOG.md](CHANGELOG.md) | Release history and version notes |
| [CLAUDE.md](CLAUDE.md) | Claude Code-specific instructions |
| [GEMINI.md](GEMINI.md) | Gemini-specific instructions |
| [Available Voices](docs/AVAILABLE_VOICES.md) | Built-in voices with canonical URIs |
| [CLI Reference](docs/CLI.md) | CLI usage and voice management |
| [Building & Testing](docs/BUILDING.md) | Build from source, test suites |
| [Echada Handoff](docs/ECHADA_VOICE_CREATION_HANDOFF.md) | Removed voice creation code for Echada migration |
