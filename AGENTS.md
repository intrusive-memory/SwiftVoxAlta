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
| **VoxAltaVoiceCache** | Actor caching loaded voice clone prompts and deserialized clone prompts for performance |
| **VoiceDesigner** | Generates voice candidates from character profiles |
| **VoiceLockManager** | Generates audio from locked voice identities |
| **CharacterAnalyzer** | LLM-based character analysis via SwiftBruja |
| **CharacterEvidenceExtractor** | Extracts evidence from screenplay elements |
| **CharacterProfile** | Structured character attributes for voice design |
| **AppleSiliconInfo** | Apple Silicon generation detection (M1-M5) and Neural Accelerator status |
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

### mlx-audio-swift Fork Notes

VoxAlta uses a pinned fork of `mlx-audio-swift` from the intrusive-memory GitHub org:

- **Repository**: `https://github.com/intrusive-memory/mlx-audio-swift.git`
- **Pinned Commit**: `eedb0f5a34163976d499814d469373cfe7e05ae3`
- **Rationale**: Fork includes VoiceDesign v1 support (via PR #23 from upstream) and voice cloning with clone prompts. Pinned to ensure reproducible builds while waiting for upstream integration.
- **Fork Basis**: Main branch + PR #23 (VoiceDesign support by INQTR)
- **Plan**: Upstream PR to base repo after fork validation and performance optimization complete

This fork enables:
- **VoiceDesign**: Text description → novel voice generation (1.7B model)
- **Voice Cloning**: Reference audio → clone prompt generation (Base 0.6B/1.7B models)
- **VoiceDesignIntegrationTests**: Full pipeline testing on-device

## Voice Design Pipeline

VoxAlta provides a complete VoiceDesign pipeline for creating custom character voices from screenplay evidence. The pipeline uses Qwen3-TTS VoiceDesign models to generate novel voices and Base models to lock and reproduce them consistently.

### Pipeline Steps

1. **Character Evidence Collection** -- Extract dialogue, parentheticals, actions, and scene headings from screenplay elements
2. **LLM Analysis** -- Use SwiftBruja to analyze character traits, age, gender, personality
3. **Profile Creation** -- Structure character attributes into `CharacterProfile`
4. **Voice Candidate Generation** -- Generate voice samples from text description (VoiceDesign model)
5. **Voice Locking** -- Extract clone prompt from selected candidate (Base model)
6. **Audio Synthesis** -- Render dialogue using locked clone prompt (Base model)

### VoiceDesigner API

`VoiceDesigner` is an enum namespace providing voice description composition and candidate generation.

#### `composeVoiceDescription(from:)`

Compose a Qwen3-TTS VoiceDesign description string from a character profile.

```swift
public static func composeVoiceDescription(from profile: CharacterProfile) -> String
```

**Parameters:**
- `profile: CharacterProfile` - The character profile to compose a description from

**Returns:** A voice description string suitable for VoiceDesign generation

**Format:** `"A {gender} voice, {ageRange}. {summary}. Voice traits: {traits joined}."`

**Example:**
```swift
let profile = CharacterProfile(
    name: "ELENA",
    gender: .female,
    ageRange: "30s",
    description: "A determined investigative journalist.",
    voiceTraits: ["warm", "confident", "slightly husky"],
    summary: "A female journalist in her 30s."
)

let description = VoiceDesigner.composeVoiceDescription(from: profile)
// Result: "A female voice, 30s. A female journalist in her 30s. Voice traits: warm, confident, slightly husky."
```

#### `generateCandidate(profile:modelManager:)`

Generate a single voice candidate from a character profile using the VoiceDesign 1.7B model.

```swift
public static func generateCandidate(
    profile: CharacterProfile,
    modelManager: VoxAltaModelManager
) async throws -> Data
```

**Parameters:**
- `profile: CharacterProfile` - The character profile to design a voice for
- `modelManager: VoxAltaModelManager` - The model manager (loads VoiceDesign model)

**Returns:** WAV audio Data (24kHz, 16-bit PCM, mono) of the generated voice candidate

**Throws:**
- `VoxAltaError.voiceDesignFailed` - Generation failed
- `VoxAltaError.modelNotAvailable` - VoiceDesign model cannot be loaded

**Example:**
```swift
let modelManager = VoxAltaModelManager()
let candidate = try await VoiceDesigner.generateCandidate(
    profile: profile,
    modelManager: modelManager
)
// Result: WAV Data (~5-10 seconds of audio)
```

#### `generateCandidates(profile:count:modelManager:)`

Generate multiple voice candidates from a character profile using parallel generation. Each candidate uses the same voice description but produces a different voice due to sampling stochasticity. Candidates are returned in index order regardless of completion order.

```swift
public static func generateCandidates(
    profile: CharacterProfile,
    count: Int = 3,
    modelManager: VoxAltaModelManager
) async throws -> [Data]
```

**Parameters:**
- `profile: CharacterProfile` - The character profile to design voices for
- `count: Int` - The number of candidates to generate (default: 3)
- `modelManager: VoxAltaModelManager` - The model manager (loads VoiceDesign model)

**Returns:** An array of WAV audio Data, one per candidate, in index order

**Throws:**
- `VoxAltaError.voiceDesignFailed` - Any generation fails
- `VoxAltaError.modelNotAvailable` - VoiceDesign model cannot be loaded

**Example:**
```swift
let candidates = try await VoiceDesigner.generateCandidates(
    profile: profile,
    count: 3,
    modelManager: modelManager
)
// Result: [Data, Data, Data] - 3 different voice samples
```

**Parallel Generation:** Candidates are generated concurrently using `withThrowingTaskGroup`. The VoiceDesign model is loaded once and shared across all tasks. Per-candidate and total wall-clock timing are logged to stderr. If any candidate fails, the TaskGroup cancels remaining tasks and propagates the first error. Observed speedup is approximately 1.7x for 2 candidates; expected 2-3x for 3 candidates depending on GPU scheduling.

### VoiceLockManager API

`VoiceLockManager` is an enum namespace providing voice lock creation and audio generation from locked voices.

#### `createLock(characterName:candidateAudio:designInstruction:modelManager:modelRepo:)`

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

**Parameters:**
- `characterName: String` - The character name to associate with this voice lock
- `candidateAudio: Data` - WAV format Data of the selected voice candidate
- `designInstruction: String` - The voice description text used to generate the candidate
- `modelManager: VoxAltaModelManager` - The model manager (loads Base model)
- `modelRepo: Qwen3TTSModelRepo` - The Base model variant (default: `.base1_7B`)

**Returns:** A `VoiceLock` containing the serialized clone prompt

**Throws:**
- `VoxAltaError.cloningFailed` - Clone prompt extraction failed
- `VoxAltaError.modelNotAvailable` - Base model cannot be loaded

**Example:**
```swift
let description = VoiceDesigner.composeVoiceDescription(from: profile)
let candidates = try await VoiceDesigner.generateCandidates(profile: profile, modelManager: modelManager)

// User selects candidates[1] as best voice
let voiceLock = try await VoiceLockManager.createLock(
    characterName: "ELENA",
    candidateAudio: candidates[1],
    designInstruction: description,
    modelManager: modelManager
)
// Result: VoiceLock with ~3-4 MB serialized clone prompt
```

**Clone Prompt Details:**
- Clone prompts contain speaker embeddings (from ECAPA-TDNN encoder) and reference audio codes
- Serialized size: ~3-4 MB per voice
- Store in SwiftData alongside character records
- Reusable across all dialogue for the character

#### `generateAudio(text:voiceLock:language:modelManager:modelRepo:cache:)`

Generate speech audio using a locked voice identity. Deserializes the clone prompt and uses it to render dialogue with the Base model. If a cache is provided, the clone prompt is retrieved from the cache if available (avoiding deserialization overhead). On cache miss, the clone prompt is deserialized and stored in the cache for subsequent calls.

```swift
public static func generateAudio(
    text: String,
    voiceLock: VoiceLock,
    language: String = "en",
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    cache: VoxAltaVoiceCache? = nil
) async throws -> Data
```

**Parameters:**
- `text: String` - The text to synthesize
- `voiceLock: VoiceLock` - The voice lock containing the serialized clone prompt
- `language: String` - The language code for generation (default: "en")
- `modelManager: VoxAltaModelManager` - The model manager (loads Base model)
- `modelRepo: Qwen3TTSModelRepo` - The Base model variant (default: `.base1_7B`)
- `cache: VoxAltaVoiceCache?` - Optional voice cache for clone prompt caching. If provided, reduces deserialization overhead on repeated calls (default: `nil`)

**Returns:** WAV format Data (24kHz, 16-bit PCM, mono) of the generated speech audio

**Throws:**
- `VoxAltaError.cloningFailed` - Generation or deserialization failed
- `VoxAltaError.modelNotAvailable` - Base model cannot be loaded

**Example:**
```swift
// Without caching (clone prompt deserialized on each call)
let audio = try await VoiceLockManager.generateAudio(
    text: "Did you get the documents?",
    voiceLock: voiceLock,
    language: "en",
    modelManager: modelManager
)
// Result: WAV Data in Elena's locked voice

// With caching (2× speedup on repeated calls)
let cache = VoxAltaVoiceCache()
let audio1 = try await VoiceLockManager.generateAudio(
    text: "First line.",
    voiceLock: voiceLock,
    language: "en",
    modelManager: modelManager,
    cache: cache  // Cache miss - deserializes and caches
)
let audio2 = try await VoiceLockManager.generateAudio(
    text: "Second line.",
    voiceLock: voiceLock,
    language: "en",
    modelManager: modelManager,
    cache: cache  // Cache hit - reuses cached clone prompt (fast!)
)
```

**Performance:**
- First generation: ~20-40s per line (includes clone prompt deserialization)
- Subsequent generations: ~10-20s per line (2× speedup via clone prompt caching)
- Cache is stored in `VoxAltaVoiceCache` actor and shared across all audio generation calls
- Cache is cleared on `unloadAllVoices()` or when a voice is removed from the cache

### Complete Pipeline Example

```swift
import SwiftVoxAlta

// Step 1: Character analysis (evidence → profile)
let evidence = CharacterEvidence(
    characterName: "ELENA",
    dialogueLines: ["Did you get the documents?", "I won't let you down."],
    parentheticals: ["determined", "quietly"],
    sceneHeadings: ["INT. OFFICE - DAY"],
    actionMentions: ["Elena paces nervously."]
)

let profile = try await CharacterAnalyzer.analyze(evidence: evidence)

// Step 2: Voice description composition
let description = VoiceDesigner.composeVoiceDescription(from: profile)

// Step 3: Generate voice candidates
let modelManager = VoxAltaModelManager()
let candidates = try await VoiceDesigner.generateCandidates(
    profile: profile,
    count: 3,
    modelManager: modelManager
)

// Step 4: Lock selected candidate (e.g., user picks candidates[1])
let voiceLock = try await VoiceLockManager.createLock(
    characterName: "ELENA",
    candidateAudio: candidates[1],
    designInstruction: description,
    modelManager: modelManager
)

// Step 5: Generate dialogue with locked voice
let audio = try await VoiceLockManager.generateAudio(
    text: "Did you get the documents?",
    voiceLock: voiceLock,
    language: "en",
    modelManager: modelManager
)

// Step 6: Store voice lock in SwiftData (app layer)
// voiceLock.clonePromptData -> SwiftData @Model character.voiceLockData
```

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

## Apple Silicon Detection API

`AppleSiliconInfo` provides runtime detection of Apple Silicon generation (M1 through M5) to identify Neural Accelerator availability for MLX performance optimizations.

### AppleSiliconGeneration Enum

Detects the current Apple Silicon chip generation at runtime via `sysctlbyname("machdep.cpu.brand_string")`.

```swift
public enum AppleSiliconGeneration: String, Sendable, CaseIterable {
    case m1, m1Pro, m1Max, m1Ultra
    case m2, m2Pro, m2Max, m2Ultra
    case m3, m3Pro, m3Max, m3Ultra
    case m4, m4Pro, m4Max, m4Ultra
    case m5, m5Pro, m5Max, m5Ultra
    case unknown

    /// Whether this chip generation includes M5 Neural Accelerators.
    public var hasNeuralAccelerators: Bool { /* true for M5 family */ }

    /// The current Apple Silicon generation detected on this system.
    public static var current: AppleSiliconGeneration { /* cached detection */ }
}
```

### Usage Example

```swift
import SwiftVoxAlta

let generation = AppleSiliconGeneration.current
print("Running on \(generation.rawValue)")

if generation.hasNeuralAccelerators {
    print("Neural Accelerators available - expect 4× TTS speedup on macOS 26.2+")
}
```

### Neural Accelerator Benefits

M5 Neural Accelerators (M5/M5 Pro/M5 Max/M5 Ultra, 2025+) provide hardware-accelerated inference for MLX workloads:

- **4× faster TTS inference** on macOS 26.2+ with zero code changes
- **Auto-detection** - MLX automatically leverages Neural Accelerators when available
- **Graceful fallback** - Works seamlessly on M1/M2/M3/M4 without Neural Accelerators
- **Logged on model load** - VoxAltaModelManager logs Neural Accelerator status to stderr

When a model is loaded on M5 hardware, VoxAlta logs:
```
Neural Accelerators detected (M5 Pro) - MLX will auto-accelerate TTS inference (4× speedup on macOS 26.2+)
```

## Design Patterns

- **VoiceProvider abstraction** -- Implements SwiftHablare's protocol for plug-and-play integration
- **Actor isolation** -- `VoxAltaModelManager` and `VoxAltaVoiceCache` are actors for thread safety
- **Lazy model loading** -- Qwen3-TTS models loaded on-demand, cached for reuse, auto-unloaded on switch
- **Memory-aware loading** -- Warns on low memory but lets macOS manage swap (non-blocking)
- **Clone prompt locking** -- `VoiceLock` ensures voice consistency across all character dialogue
- **Parallel voice generation** -- `generateCandidates()` uses `withThrowingTaskGroup` for concurrent candidate generation with index-ordered results and first-error propagation
- **On-device inference** -- All LLM and TTS processing runs locally via Apple Silicon GPU
- **Strict concurrency** -- Swift 6 language mode with `StrictConcurrency` enabled

## Memory Management

- **Model caching** -- TTS models cached at `~/Library/SharedModels/` via SwiftAcervo
- **Lazy loading** -- Models loaded only when needed for synthesis
- **Memory checks** -- `VoxAltaModelManager.checkMemory()` warns on low memory via stderr
- **Single-model cache** -- Only one TTS model loaded at a time; switching unloads the previous
- **Voice cache** -- `VoxAltaVoiceCache` actor stores loaded clone prompts (serialized Data) in memory
- **Clone prompt cache** -- Deserialized `VoiceClonePrompt` instances cached to avoid repeated deserialization overhead (2× speedup)

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
  - **VoiceDesign integration tests** (`VoiceDesignIntegrationTests.swift`): Full pipeline validation (profile → description → candidates → lock → audio generation, WAV format validation, clone prompt serialization round-trip). Disabled on CI due to Metal compiler limitations.
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
