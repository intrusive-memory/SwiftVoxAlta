<p align="center">
  <img src="swift-vox-alta.jpg" alt="SwiftVoxAlta Logo" width="400">
</p>

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

### M5 Neural Accelerator Support

SwiftVoxAlta automatically detects and leverages **M5 Neural Accelerators** (Apple M5/M5 Pro/M5 Max/M5 Ultra chips, 2025+) for significant TTS performance improvements:

- **4× faster inference** on macOS 26.2+ with M5 chips
- **Zero code changes required** - MLX auto-detects Neural Accelerators at runtime
- **Automatic fallback** - Works seamlessly on M1/M2/M3/M4 without Neural Accelerators

When a model is loaded on M5 hardware, VoxAlta logs: `Neural Accelerators detected (M5 Pro) - MLX will auto-accelerate TTS inference (4× speedup on macOS 26.2+)`

## Installation

### Homebrew (CLI tool)

```bash
brew tap intrusive-memory/tap
brew install diga
```

### Swift Package Manager (library)

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftVoxAlta.git", from: "0.5.0")
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
diga --import-vox elena.vox                            # Import .vox file
diga -v elena.vox "Hello"                              # Synthesize from .vox directly

# Model selection
diga --model 0.6b "Hello"   # Smaller model (<16GB RAM)
diga --model 1.7b "Hello"   # Larger model (better quality)
```

On first run, `diga` auto-downloads the appropriate Qwen3-TTS model (~2-4 GB) from HuggingFace.

## Portable Voice Files (.vox)

VoxAlta uses the `.vox` format for portable voice identity files. A `.vox` is a ZIP archive containing:

- **Manifest** -- Voice metadata (name, description, provenance)
- **Reference audio** -- Source audio for cloned voices
- **Embeddings** -- Clone prompt (`qwen3-tts/clone-prompt.bin`) and sample audio (`qwen3-tts/sample-audio.wav`)

When you create a voice with `--design` or `--clone`, a `.vox` file is automatically exported to `~/.diga/voices/`. The CLI synthesizes a phoneme pangram, plays it through speakers so you can hear the voice immediately, and embeds the sample into the `.vox` file.

```bash
# Create a voice -- hear it immediately, .vox saved automatically
diga --design "warm male baritone, 40s" narrator

# Import a .vox from someone else
diga --import-vox narrator.vox

# Use a .vox directly without importing
diga -v narrator.vox "Hello, world!"

# Inspect a .vox file
unzip -l ~/.diga/voices/narrator.vox
```

## Migration from v0.2.x

**Breaking Change (v0.3.0)**: Git LFS models have been removed from the repository. Models are now downloaded at runtime via [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) to `~/Library/SharedModels/`.

- **Before v0.3.0**: Models were stored in `Models/` directory with Git LFS (~4.5 GB in repo)
- **After v0.3.0**: Models are downloaded on first use to `~/Library/SharedModels/` (~8.5 GB shared across all apps)

**Benefits**:
- Faster `git clone` (no LFS downloads)
- Shared model cache across multiple projects
- CI/CD caching support (models cached between runs)

**Action Required**: If you have a local clone from v0.2.x or earlier, the old `Models/` directory is no longer used. You can safely delete it.

## Building from Source

**Important**: Use `xcodebuild` or the Makefile. Metal shaders required by Qwen3-TTS won't compile with `swift build`.

```bash
make build      # Development build
make release    # Release build + copy to ./bin
make install    # Debug build + copy to ./bin
```

## Testing

VoxAlta has two test suites: fast unit tests and slower integration tests.

### Test Targets

```bash
# Fast unit tests (library only, no binary required, ~5-10 seconds)
make test-unit

# Integration tests (builds diga binary, requires models/voices, ~15-60 seconds)
make test-integration

# Run both test suites sequentially
make test
```

**Unit tests** (`make test-unit`) validate the VoxAlta library code (voice design API, audio processing, character analysis) without requiring the `diga` binary. These are fast and suitable for rapid iteration during development.

**Integration tests** (`make test-integration`) spawn the `diga` binary as a subprocess and validate:
- Binary execution and command-line parsing
- Audio file generation (WAV, AIFF, M4A formats)
- File headers and format validation
- Audio quality (non-silence detection via RMS/peak analysis)

### Voice Cache Behavior

Integration tests use voice caching to avoid repeated generation costs:

**First run** (cold cache):
- Auto-downloads Qwen3-TTS models from HuggingFace (~3-4 GB one-time download)
- Auto-generates test voice "alex" (~60 seconds one-time cost)
- Caches voice at `~/Library/Caches/intrusive-memory/Voices/alex.voice`
- Total time: ~60-90 seconds

**Subsequent runs** (warm cache):
- Reuses cached voice from disk (instant load)
- Total time: ~15 seconds

Voice caches persist across test runs. Clear the cache to force regeneration:

```bash
rm -rf ~/Library/Caches/intrusive-memory/Voices/
```

### Local Development Workflow

**During active development:**
```bash
make test-unit  # Fast feedback loop (~5s)
```

**Before submitting a pull request:**
```bash
make test  # Runs both unit and integration tests
```

**First-time setup:**
```bash
make install  # Build diga binary
make test-integration  # Generate voice cache (one-time ~60s)
```

After the initial setup, integration tests will use the cached voice and complete in ~15 seconds.

### CI Behavior

GitHub Actions runs unit and integration tests in parallel jobs:

**Unit Tests Job:**
- Runs on `macos-26` runner
- No model download or voice generation required
- Completes in ~10 seconds

**Integration Tests Job:**
- Runs on `macos-26` runner
- Uses GitHub Actions cache for models and voices
- First CI run: Downloads models and generates voices (~90 seconds)
- Subsequent CI runs: Uses cached models/voices (~15 seconds)
- Uploads test audio artifacts on failure for debugging

Cache key: `tts-cache-v1` (shared across CI runs)

## VoiceDesign Character Voice Pipeline

VoxAlta provides a complete character voice pipeline for designing custom voices from character profiles using Qwen3-TTS VoiceDesign technology.

### Pipeline Overview

The VoiceDesign pipeline follows these steps:

1. **Character Analysis** - Extract character traits from screenplay evidence
2. **Voice Description** - Compose text description from character profile
3. **Candidate Generation** - Generate 3 voice candidates with VoiceDesign model
4. **Voice Locking** - Create clone prompt from selected candidate
5. **Audio Generation** - Render dialogue using locked voice identity

### Complete Workflow Example

```swift
import SwiftVoxAlta
import SwiftCompartido

// Step 1: Collect character evidence from screenplay
let evidence = CharacterEvidence(
    characterName: "ELENA",
    dialogueLines: [
        "Did you get the documents?",
        "I won't let you down.",
        "Trust me on this."
    ],
    parentheticals: ["determined", "quietly", "nervous"],
    sceneHeadings: ["INT. OFFICE - DAY", "INT. PARKING LOT - NIGHT"],
    actionMentions: ["Elena paces nervously.", "Elena's hands shake as she opens the file."]
)

// Step 2: Analyze character with LLM (via SwiftBruja)
let profile = try await CharacterAnalyzer.analyze(evidence: evidence)
// Result: CharacterProfile with gender, ageRange, voiceTraits, summary

// Step 3: Compose voice description from profile
let description = VoiceDesigner.composeVoiceDescription(from: profile)
// Result: "A female voice, 30s. A determined investigative journalist. Voice traits: warm, confident, slightly husky."

// Step 4: Generate 3 voice candidates
let modelManager = VoxAltaModelManager()
let candidates = try await VoiceDesigner.generateCandidates(
    profile: profile,
    count: 3,
    modelManager: modelManager
)
// Result: [Data] - 3 WAV audio samples, each with a slightly different voice

// Step 5: Lock selected candidate (e.g., user picks candidates[1])
let voiceLock = try await VoiceLockManager.createLock(
    characterName: "ELENA",
    candidateAudio: candidates[1],
    designInstruction: description,
    modelManager: modelManager
)
// Result: VoiceLock with serialized clone prompt data

// Step 6: Generate dialogue with locked voice
let context = GenerationContext(phrase: "Did you get the documents?")
let audio = try await VoiceLockManager.generateAudio(
    context: context,
    voiceLock: voiceLock,
    language: "en",
    modelManager: modelManager
)
// Result: WAV Data in Elena's locked voice (24kHz, 16-bit PCM, mono)
```

### Model Requirements

The VoiceDesign pipeline requires two Qwen3-TTS models:

| Model | Size | Purpose | Download |
|-------|------|---------|----------|
| VoiceDesign 1.7B | 4.2 GB | Generate voice candidates from text descriptions | Auto-downloaded on first use |
| Base 1.7B | 4.3 GB | Clone voices and render dialogue from clone prompts | Auto-downloaded on first use |

**Total disk space**: ~8.5 GB (models cached at `~/Library/SharedModels/`)

Models are downloaded automatically from HuggingFace on first use via SwiftAcervo.

### Character Profile Structure

```swift
public struct CharacterProfile: Sendable, Codable {
    public let name: String
    public let gender: Gender              // .male, .female, .nonBinary, .unknown
    public let ageRange: String            // e.g., "30s", "mid-40s", "elderly"
    public let description: String         // Character description from screenplay
    public let voiceTraits: [String]       // e.g., ["warm", "confident", "husky"]
    public let summary: String             // One-line character summary
}
```

### Voice Lock Persistence

`VoiceLock` instances are designed for SwiftData persistence in Produciesta:

```swift
public struct VoiceLock: Sendable, Codable {
    public let characterName: String
    public let clonePromptData: Data      // Serialized VoiceClonePrompt (~3-4 MB)
    public let designInstruction: String  // Original voice description
    public let lockedAt: Date
}
```

Store `VoiceLock.clonePromptData` in SwiftData alongside character records. Locked voices ensure the same character sounds identical across all dialogue in all scenes.

### Troubleshooting

**Model download fails**
- Check internet connection (models download from HuggingFace)
- Verify disk space (~8.5 GB required)
- Check `~/Library/SharedModels/` permissions

**Voice quality issues**
- Use Base 1.7B model (not 0.6B) for best quality
- Ensure character profile has detailed voiceTraits
- Generate 3+ candidates and pick the best one

**Out of memory errors**
- VoiceDesign requires 16 GB+ RAM (Apple Silicon unified memory)
- Close other apps during voice generation
- Use Base 0.6B model if system has <16 GB RAM

**Voice inconsistency across dialogue**
- Always use the same VoiceLock for all dialogue from a character
- Never regenerate clone prompts - reuse the locked prompt
- Verify locked voice before rendering full screenplay

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
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) -- Input types (GuionElementModel, ElementType)
- [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) -- LLM inference for character analysis
- [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) -- Qwen3-TTS inference
- [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) -- Shared model management and caching
- [vox-format](https://github.com/intrusive-memory/vox-format) -- Portable `.vox` voice identity file format

## License

MIT
