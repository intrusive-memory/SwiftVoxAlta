# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftVoxAlta codebase.

**Current Version**: 0.2.1

---

## Project Overview

SwiftVoxAlta is a VoiceProvider library for SwiftHablare that provides on-device voice design and cloning capabilities using Qwen3-TTS via mlx-audio-swift.

**Purpose**: Analyze screenplay characters, design custom voices, lock voice identities through cloning, and render dialogue audio -- all on-device using Apple Silicon.

## What VoxAlta Provides

- **VoiceProvider implementation** -- text + voiceId -> audio Data (Qwen3-TTS base model cloning)
- **Voice design API** -- character evidence -> CharacterProfile -> voice candidates -> locked voice
- **VoiceProviderDescriptor** -- auto-registration with SwiftHablare's provider registry
- **CLI tool (`diga`)** -- drop-in replacement for `/usr/bin/say` with neural TTS

## What VoxAlta Does NOT Provide

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
.package(url: "https://github.com/intrusive-memory/SwiftVoxAlta.git", from: "0.1.0")
```

## Project Structure

```
SwiftVoxAlta/
├── Sources/
│   ├── SwiftVoxAlta/                  # Library target
│   │   ├── AudioConversion.swift      # WAV format utilities
│   │   ├── CharacterAnalyzer.swift    # LLM-based character analysis
│   │   ├── CharacterEvidenceExtractor.swift  # Extract evidence from screenplay
│   │   ├── CharacterProfile.swift     # CharacterProfile + CharacterEvidence types
│   │   ├── ParentheticalMapper.swift  # Map parentheticals to voice traits
│   │   ├── VoiceDesigner.swift        # Voice candidate generation
│   │   ├── VoiceLock.swift            # Locked voice identity type
│   │   ├── VoiceLockManager.swift     # Audio generation from locked voices
│   │   ├── VoxAltaConfig.swift        # Configuration (model IDs, output format)
│   │   ├── VoxAltaError.swift         # Error types
│   │   ├── VoxAltaModelManager.swift  # Qwen3-TTS model lifecycle (actor)
│   │   ├── VoxAltaProviderDescriptor.swift  # SwiftHablare registration
│   │   ├── VoxAltaVoiceCache.swift    # Thread-safe voice cache (actor)
│   │   └── VoxAltaVoiceProvider.swift # VoiceProvider protocol implementation
│   └── diga/                          # CLI executable target
│       ├── AudioFileWriter.swift      # WAV/AIFF/M4A file output
│       ├── AudioPlayback.swift        # Speaker playback via AVAudioPlayer
│       ├── BuiltinVoices.swift        # Built-in voice presets
│       ├── DigaCommand.swift          # CLI entry point and argument parsing
│       ├── DigaEngine.swift           # Synthesis engine (text -> WAV data)
│       ├── DigaModelManager.swift     # Model download and cache management
│       ├── TextChunker.swift          # Split long text for chunked synthesis
│       ├── Version.swift              # Version constant (0.2.1)
│       └── VoiceStore.swift           # Persistent custom voice storage
├── Tests/
│   ├── SwiftVoxAltaTests/             # Library tests
│   └── DigaTests/                     # CLI tests
├── Formula/
│   └── diga.rb                        # Reference Homebrew formula
├── Makefile                           # Build targets (xcodebuild wrapper)
├── Package.swift
├── AGENTS.md                          # This file
├── CLAUDE.md                          # Claude Code pointer -> AGENTS.md
├── GEMINI.md                          # Gemini pointer -> AGENTS.md
└── README.md
```

## Key Components

| Component | Purpose |
|-----------|---------|
| **VoxAltaVoiceProvider** | Implements SwiftHablare's `VoiceProvider` protocol |
| **VoxAltaModelManager** | Actor managing Qwen3-TTS model lifecycle via mlx-audio-swift |
| **VoxAltaVoiceCache** | Actor caching loaded voice clone prompts |
| **VoiceDesigner** | Generates voice candidates from character profiles |
| **VoiceLockManager** | Generates audio from locked voice identities |
| **CharacterAnalyzer** | LLM-based character analysis via SwiftBruja |
| **CharacterEvidenceExtractor** | Extracts evidence from screenplay elements |
| **CharacterProfile** | Structured character attributes for voice design |
| **VoxAltaConfig** | Configuration (model IDs, candidate count, output format) |
| **VoxAltaProviderDescriptor** | Factory for SwiftHablare registry registration |
| **`diga` CLI** | Drop-in `say` replacement with neural TTS |

## Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) | VoiceProvider protocol and registry |
| [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) | Input types (GuionElementModel, ElementType) |
| [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) | LLM inference for character analysis |
| [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) | Qwen3-TTS inference engine (MLXAudioTTS) |
| [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) | Shared model management and caching |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI argument parsing |

## Voice Design Pipeline

1. **Character Evidence Collection** -- Extract dialogue, parentheticals, actions, and scene headings from screenplay elements
2. **LLM Analysis** -- Use SwiftBruja to analyze character traits, age, gender, personality
3. **Profile Creation** -- Structure character attributes into `CharacterProfile`
4. **Voice Candidate Generation** -- Generate VoiceDesign descriptions based on profile
5. **Voice Locking** -- Select candidate and lock voice identity as a `VoiceLock` with clone prompt data
6. **Audio Synthesis** -- Render dialogue using Qwen3-TTS Base model with the locked clone prompt

## Build and Test

**CRITICAL**: Use `xcodebuild` or the Makefile for all builds and tests. Qwen3-TTS requires Metal shaders which don't compile with `swift build`.

### Makefile Targets

```bash
make build      # Development build (xcodebuild debug)
make install    # Debug build + copy binary and Metal bundle to ./bin
make release    # Release build + copy to ./bin
make test       # Run all tests (library + CLI)
make resolve    # Resolve SPM dependencies
make clean      # Clean build artifacts
```

### Direct xcodebuild

```bash
# Build library
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS'

# Run tests
xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS'

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

### Protocol Conformance

```swift
public protocol VoiceProvider {
    var providerId: String { get }

    func fetchVoices(languageCode: String) async throws -> [Voice]
    func isVoiceAvailable(voiceId: String) async -> Bool
    func generateAudio(text: String, voiceId: String, languageCode: String) async throws -> Data
    func generateProcessedAudio(text: String, voiceId: String, languageCode: String) async throws -> ProcessedAudio
}
```

### Dual-Mode Routing

VoxAltaVoiceProvider automatically routes voice generation requests based on voice type:

1. **Route 1 (Preset speakers)** -- Direct CustomVoice model generation - fast, no setup required:
   ```swift
   let audio = try await provider.generateAudio(
       text: "Hello",
       voiceId: "ryan",  // Routes through Route 1
       languageCode: "en"
   )
   ```
   Supports: `ryan`, `aiden`, `vivian`, `serena`, `uncle_fu`, `dylan`, `eric`, `anna`, `sohee`

2. **Route 2 (Clone prompts)** -- For custom voices loaded via `loadVoice()` - requires voice lock:
   ```swift
   await provider.loadVoice(id: "ELENA", clonePromptData: lockData, gender: "female")
   let audio = try await provider.generateAudio(
       text: "Hello",
       voiceId: "ELENA",  // Routes through Route 2
       languageCode: "en"
   )
   ```

### Multilingual Voice Support

**All preset speakers are fully multilingual with English as their primary language.**

While voice descriptions reference ethnic or regional characteristics (e.g., "Chinese female voice", "Japanese female voice"), **all 9 preset speakers have English as their first language** and their indicated regional language as a secondary language. This means:

- **English requests return all voices** -- `fetchVoices(languageCode: "en")` returns all 9 preset speakers
- **No language filtering** -- The `languageCode` parameter labels voices but does not filter them
- **Universal availability** -- All voices work seamlessly for English text synthesis regardless of their descriptive labels

Voice characteristics (e.g., "Chinese", "Japanese", "Korean") describe accent, prosody, and timbral qualities rather than exclusive language support.

**Example:**
```swift
// All 9 preset speakers are returned for English
let voices = try await provider.fetchVoices(languageCode: "en")
// voices.count == 9 (plus any loaded custom voices)

// Same voices are returned for other languages (just labeled differently)
let voicesZh = try await provider.fetchVoices(languageCode: "zh")
// voicesZh.count == 9 (same voices, language field set to "zh")
```

### Integration with Produciesta

VoxAlta integrates transparently with Produciesta:

- **Auto-registration** -- VoxAlta registers automatically with VoiceProviderRegistry on app startup
- **Preset voices** -- All 9 CustomVoice speakers appear in voice selection dropdowns immediately
- **No configuration** -- Works out-of-the-box with no additional setup
- **On-device inference** -- All audio generation runs locally on Apple Silicon

See **[Produciesta Integration Guide](../docs/PRODUCIESTA_INTEGRATION.md)** for complete integration instructions.

### API Usage

```swift
import SwiftVoxAlta
import SwiftHablare

// Create provider
let provider = VoxAltaVoiceProvider()

// Fetch available voices (includes 9 presets + any loaded custom voices)
let voices = try await provider.fetchVoices(languageCode: "en")

// Check voice availability
let available = await provider.isVoiceAvailable(voiceId: "ryan")

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

// Generate with duration measurement (returns ProcessedAudio)
let processed = try await provider.generateProcessedAudio(
    text: "Hello!",
    voiceId: "ryan",
    languageCode: "en"
)
// processed.audioData, processed.durationSeconds, processed.mimeType
```

### Voice Design API

```swift
import SwiftVoxAlta

// Collect character evidence from screenplay
let evidence = CharacterEvidence(
    characterName: "ELENA",
    dialogueLines: ["I won't let you down.", "Trust me on this."],
    parentheticals: ["determined", "quietly"],
    sceneHeadings: ["INT. OFFICE - DAY"],
    actionMentions: ["Elena paces nervously."]
)

// Analyze character via LLM
let profile = try await CharacterAnalyzer.analyze(evidence: evidence)

// Generate voice candidates
let candidates = try await VoiceDesigner.generateCandidates(profile: profile)

// Lock voice identity
let lock = VoiceLock(
    characterName: profile.name,
    clonePromptData: candidates[0].clonePromptData,
    designInstruction: candidates[0].designDescription
)
```

### SwiftHablare Registration

```swift
import SwiftHablare
import SwiftVoxAlta

// Register VoxAlta with the provider registry
let registry = VoiceProviderRegistry.shared
await registry.register(VoxAltaProviderDescriptor.descriptor())

// VoxAlta provider is now available with id "voxalta"
```

## CLI Tool (`diga`)

`diga` is a drop-in replacement for `/usr/bin/say` with neural text-to-speech via Qwen3-TTS.

**See [Available Voices Documentation](docs/AVAILABLE_VOICES.md)** for a complete list of built-in voices, canonical URIs for voice casting, and voice management details.

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

# Design a new voice from description
diga --design "warm female voice, 30s, confident" elena

# Clone a voice from reference audio
diga --clone reference.wav elena

# Override model selection
diga --model 0.6b "Hello"     # Use smaller model
diga --model 1.7b "Hello"     # Use larger model
```

### CLI Flags

| Flag | Short | Purpose |
|------|-------|---------|
| `--voices` | | List all available voices |
| `--voice <name>` | `-v` | Select voice for synthesis |
| `--design <desc>` | | Create voice from text description |
| `--clone <file>` | | Clone voice from reference audio |
| `--output <path>` | `-o` | Write to file (WAV/AIFF/M4A) |
| `--file <path>` | `-f` | Read input from file (`-` for stdin) |
| `--file-format <fmt>` | | Override output format (wav, aiff, m4a) |
| `--model <id>` | | Override model (0.6b, 1.7b, or HF repo) |
| `--version` | | Show version |
| `--help` | `-h` | Show help |

## Qwen3-TTS Models

| Model | Repo ID | Size | Use Case |
|-------|---------|------|----------|
| VoiceDesign 1.7B | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` | ~4.2 GB | Generate voices from text descriptions |
| Base 1.7B | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` | ~4.3 GB | Voice cloning (recommended) |
| Base 0.6B | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` | ~2.4 GB | Voice cloning (lighter, <16GB RAM) |

- Models are auto-downloaded on first use from HuggingFace
- Cached at `~/Library/SharedModels/` (via SwiftAcervo), shared across the intrusive-memory ecosystem
- Legacy models at `~/Library/Caches/intrusive-memory/Models/TTS/` are auto-migrated on first use
- `diga` auto-selects 1.7B (>=16GB RAM) or 0.6B (<16GB RAM)

## Error Types

```swift
public enum VoxAltaError: Error {
    case voiceDesignFailed(String)           // Voice design generation failed
    case cloningFailed(String)               // Voice cloning from reference audio failed
    case modelNotAvailable(String)           // TTS model not available or download failed
    case voiceNotLoaded(String)              // Voice not in cache (call loadVoice first)
    case profileAnalysisFailed(String)       // LLM character analysis failed
    case insufficientMemory(available:required:) // Not enough RAM for model
    case audioExportFailed(String)           // Audio format conversion failed
}
```

## Design Patterns

- **VoiceProvider abstraction** -- Implements SwiftHablare's protocol for plug-and-play integration
- **Actor isolation** -- `VoxAltaModelManager` and `VoxAltaVoiceCache` are actors for thread safety
- **Lazy model loading** -- Qwen3-TTS models loaded on-demand, cached for reuse, auto-unloaded on switch
- **Memory-aware loading** -- Warns on low memory but lets macOS manage swap (non-blocking)
- **Clone prompt locking** -- `VoiceLock` ensures voice consistency across all character dialogue
- **On-device inference** -- All LLM and TTS processing runs locally via Apple Silicon GPU
- **Strict concurrency** -- Swift 6 language mode with `StrictConcurrency` enabled

## Memory Management

- **Model caching** -- TTS models cached at `~/Library/SharedModels/` via SwiftAcervo
- **Lazy loading** -- Models loaded only when needed for synthesis
- **Memory checks** -- `VoxAltaModelManager.checkMemory()` warns on low memory via stderr
- **Single-model cache** -- Only one TTS model loaded at a time; switching unloads the previous
- **Voice cache** -- `VoxAltaVoiceCache` actor stores loaded clone prompts in memory

## Development Workflow

- **Branch**: `development` -> PR -> `main`
- **CI Required**: Build + Integration Tests + Audio Integration Test must pass before merge
- **CI Architecture**: See [CI Dependency Chain](docs/CI_DEPENDENCY_CHAIN.md) for parallel voice caching + sequential test execution
- **Never commit directly to `main`**
- **Platforms**: macOS 26+, iOS 26+ only (Apple Silicon required)
- **NEVER add `@available` attributes** for older platforms
- **CI runner**: `macos-26`

## Release Process

1. Tag on `main` (e.g., `v0.1.1`)
2. GitHub Release triggers `.github/workflows/release.yml`
3. Release workflow: `make release` -> tarball -> upload assets -> dispatch to `intrusive-memory/homebrew-tap`
4. Homebrew tap auto-updates formula with new URL and SHA256

## Testing

- **Library tests** (`SwiftVoxAltaTests/`): VoiceProvider, model manager, voice cache, character analysis, error paths, audio conversion, voice design, voice lock, Acervo integration
- **CLI tests** (`DigaTests/`): CLI integration, audio file writer, audio playback, engine, model manager (Acervo-backed), voice store, version, release checks
- **Binary integration tests** (`DigaBinaryIntegrationTests`): End-to-end audio generation validation (WAV/AIFF/M4A formats, silence detection, error handling)
- **359 total tests** (229 library + 130 CLI)
- **CI Test Execution**: See [CI Dependency Chain](docs/CI_DEPENDENCY_CHAIN.md) for parallel voice caching strategy and test dependencies

## Important Notes

- **Apple Silicon required** -- Qwen3-TTS via MLX requires M1/M2/M3/M4 GPU
- **Metal shaders required** -- Must build with `xcodebuild` (not `swift build`)
- **Model downloads** -- First use auto-downloads Qwen3-TTS (~2-4 GB per model)
- **Character consistency** -- Locked voices ensure same character sounds identical across scenes
- **Privacy** -- All processing on-device, no cloud APIs
- **Experimental status** -- VoxAlta is in active development, APIs may change

## Documentation Index

| Document | Purpose |
|----------|---------|
| [AGENTS.md](AGENTS.md) | This file - complete project documentation and development guidelines |
| [CLAUDE.md](CLAUDE.md) | Claude Code quick reference pointer to AGENTS.md |
| [Available Voices](docs/AVAILABLE_VOICES.md) | **Complete list of built-in voices with canonical URIs for voice casting** |
| [CI Dependency Chain](docs/CI_DEPENDENCY_CHAIN.md) | Parallel voice caching and test execution strategy |
| [CustomVoice Execution Plan](docs/CUSTOMVOICE_EXECUTION_PLAN.md) | CustomVoice implementation plan |
| [CustomVoice Migration](docs/CUSTOMVOICE_MIGRATION.md) | Migration guide from Base/VoiceDesign to CustomVoice |
