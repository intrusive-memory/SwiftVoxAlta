# AGENTS.md

Documentation for AI agents working with the SwiftVoxAlta codebase.

**Current Version**: 0.10.9-dev

---

## Project Overview

SwiftVoxAlta is a **speech synthesis** library. It consumes `.vox` voice identity files and renders text to audio using Qwen3-TTS on Apple Silicon. It does **not** create, design, or clone voices.

### Voice Creation vs Voice Synthesis (Critical Distinction)

| Concern | Handled By | NOT Handled By |
|---------|-----------|----------------|
| Designing a voice from a text description | **SwiftEchada** (`echada cast`) | VoxAlta |
| Cloning a voice from reference audio | **SwiftEchada** (`echada cast`) | VoxAlta |
| Character analysis from screenplays | **SwiftEchada** | VoxAlta |
| Packaging voice identity into `.vox` files | **SwiftEchada** | VoxAlta |
| **Consuming `.vox` files for speech synthesis** | **VoxAlta** | SwiftEchada |
| **Rendering text to audio (WAV)** | **VoxAlta** | SwiftEchada |
| **Preset speaker generation (9 built-in voices)** | **VoxAlta** | SwiftEchada |

The pipeline is: `echada cast` creates a `.vox` file -> `diga --import-vox voice.vox` imports it -> `diga -v voice "text"` synthesizes speech.

### What VoxAlta Provides

- **Speech synthesis** -- text + voiceId -> WAV audio Data (24kHz, 16-bit PCM, mono)
- **VoiceProvider for SwiftHablare** -- plug-and-play integration with the voice provider registry
- **`.vox` file consumption** -- import `.vox` archives created by SwiftEchada, extract clone prompts
- **9 preset speakers** -- built-in CustomVoice speakers that work without any `.vox` file
- **GenerationSettings** -- tunable sampling parameters (temperature, topP, repetitionPenalty, maxTokens)
- **CLI tool (`diga`)** -- drop-in replacement for `/usr/bin/say` with neural TTS

### What VoxAlta Does NOT Provide

- **Voice creation of any kind** -- no voice design, no voice cloning, no character analysis. Use SwiftEchada (`echada cast`) for all voice creation, which produces `.vox` files for VoxAlta to consume.
- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage/persistence (Produciesta / SwiftData)
- Parallel generation (single GPU thread per generation; hardware limitation)

---

## App Group configuration (required)

This package depends on [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) for shared model storage. SwiftAcervo v0.10.0 resolves its App Group ID in this order: `ACERVO_APP_GROUP_ID` env var → `com.apple.security.application-groups` entitlement (macOS only) → `fatalError`. There is **no silent fallback**.

- **Signed UI apps (macOS / iOS)**: declare `com.apple.security.application-groups` with `group.intrusive-memory.models` in your `.entitlements` file. iOS apps additionally need `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the launch environment.
- **CLI tools, scripts, CI jobs, test runners**: export `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the shell or job environment. The standard place is `~/.zprofile`:

    ```sh
    export ACERVO_APP_GROUP_ID=group.intrusive-memory.models
    ```

Without this, `Acervo.sharedModelsDirectory` traps with `fatalError`. See [SwiftAcervo's USAGE.md](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) for full details.

---

## Build and Test

**CRITICAL**: Use `xcodebuild` or the Makefile. Metal shaders required by Qwen3-TTS do not compile with `swift build`.

### Makefile Targets

```bash
make build           # Development build (xcodebuild debug)
make install         # Debug build + copy binary and Metal bundle to ./bin
make release         # Release build + copy to ./bin
make test            # Run all tests (unit + integration)
make test-unit       # Fast unit tests only (~5-10 seconds, no binary required)
make test-integration # Binary integration tests (requires binary + cached voices)
make resolve         # Resolve SPM dependencies
make clean           # Clean build artifacts + DerivedData
make setup-voices    # One-time: download CustomVoice model (~3.4GB)
make help            # Show all targets
```

### Direct xcodebuild

```bash
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS,arch=arm64'
xcodebuild build -scheme diga -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS,arch=arm64'
```

### Platform Requirements

- **macOS 26.0+** / **iOS 26.0+** (Apple Silicon only)
- **Swift 6.2+** / **Xcode 26+**
- **NEVER** add `@available` attributes for older platforms
- CI runner: `macos-26`

---

## Project Structure

```
SwiftVoxAlta/
├── Sources/
│   ├── SwiftVoxAlta/                  # Library target
│   │   ├── AppleSiliconInfo.swift     # M1-M5 generation detection (21 cases)
│   │   ├── AudioConversion.swift      # MLXArray <-> WAV Data conversion
│   │   ├── GenerationContext.swift    # TTS generation envelope (phrase + metadata)
│   │   ├── GenerationSettings.swift   # Sampling parameters (temperature, topP, etc.)
│   │   ├── VoiceLock.swift            # Locked voice identity (clone prompt + metadata)
│   │   ├── VoiceLockManager.swift     # Audio generation from locked voices
│   │   ├── VoxAltaConfig.swift        # Configuration (model IDs, output format)
│   │   ├── VoxAltaError.swift         # Error types (7 cases)
│   │   ├── VoxAltaModelManager.swift  # Qwen3-TTS model lifecycle (actor)
│   │   ├── VoxAltaProviderDescriptor.swift  # SwiftHablare registration factory
│   │   ├── VoxAltaVoiceCache.swift    # Thread-safe voice + clone prompt cache (actor)
│   │   ├── VoxAltaVoiceProvider.swift # VoiceProvider protocol implementation
│   │   ├── VoxExporter.swift          # Add/update clone prompts and sample audio in .vox
│   │   └── VoxImporter.swift          # Import .vox archives, extract voice identity data
│   └── diga/                          # CLI executable target
│       ├── AudioFileWriter.swift      # WAV/AIFF/M4A file output
│       ├── AudioPlayback.swift        # Speaker playback + streaming chunked playback
│       ├── BuiltinVoices.swift        # 9 built-in CustomVoice preset speakers
│       ├── DigaCommand.swift          # CLI entry point (@main, ArgumentParser)
│       ├── DigaEngine.swift           # Synthesis orchestrator (text -> chunked WAV)
│       ├── TextChunker.swift          # Sentence-boundary chunking (NLTokenizer)
│       ├── Version.swift              # Version constant (0.10.9)
│       └── VoiceStore.swift           # Persistent custom voice storage (~/.diga/voices/)
├── Tests/
│   ├── SwiftVoxAltaTests/             # 11 test files (library)
│   └── DigaTests/                     # 8 test files (CLI)
├── .github/workflows/
│   ├── tests.yml                      # CI: unit tests on PR (macos-26)
│   └── release.yml                    # CD: build tarball, upload assets, trigger Homebrew tap
├── Formula/diga.rb                    # Reference Homebrew formula
├── Makefile                           # Build targets (xcodebuild wrapper)
├── Package.swift                      # Swift 6.2, macOS 26+, iOS 26+
├── AGENTS.md                          # This file
├── CLAUDE.md                          # Claude Code-specific instructions
├── GEMINI.md                          # Gemini-specific instructions
├── CHANGELOG.md                       # Release history
└── README.md
```

---

## Dependencies

| Package | Source | Branch/Version | Purpose |
|---------|--------|---------------|---------|
| [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) | intrusive-memory | `development` | VoiceProvider protocol and registry |
| [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) | intrusive-memory (fork) | `development` | Qwen3-TTS inference engine (MLXAudioTTS) |
| [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) | intrusive-memory | `main` | Shared model management and caching |
| [vox-format](https://github.com/intrusive-memory/vox-format) | intrusive-memory | `development` | Portable `.vox` voice identity file format |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | apple | `>= 1.5.0` | CLI argument parsing |
| [EventSource](https://github.com/intrusive-memory/EventSource) | intrusive-memory | `xcode26-transitive-fix` | Override: fixes Xcode 26 transitive dep issue with swift-huggingface |

### mlx-audio-swift Fork

Fork from `intrusive-memory` org (not upstream). Includes:
- Voice cloning: reference audio -> clone prompt generation (Base models)
- `VoiceClonePrompt.serialize()` / `.deserialize(from:)` for clone prompt persistence
- `Qwen3TTSModel.generateWithClonePrompt()` for clone-prompt-based generation
- Preset speakers: CustomVoice model with 9 built-in speakers
- `instruct` parameter support for performance directions

---

## Library API Surface

### VoxAltaVoiceProvider

Implements SwiftHablare's `VoiceProvider` protocol with dual-mode routing.

```swift
public final class VoxAltaVoiceProvider: VoiceProvider, @unchecked Sendable {
    public static let version = "0.10.9"

    // VoiceProvider protocol properties
    public let providerId = "voxalta"
    public let displayName = "VoxAlta (On-Device)"
    public let requiresAPIKey = false
    public let mimeType = "audio/wav"
    public var defaultVoiceId: String? { nil }

    public init(
        modelManager: VoxAltaModelManager = VoxAltaModelManager(),
        baseModelRepo: Qwen3TTSModelRepo = .base1_7B,
        customVoiceModelRepo: Qwen3TTSModelRepo = .customVoice1_7B,
        generationSettings: GenerationSettings = .default
    )

    // VoiceProvider protocol methods
    public func isConfigured() async -> Bool
    public func fetchVoices(languageCode: String) async throws -> [Voice]
    public func generateAudio(text: String, voiceId: String, languageCode: String) async throws -> Data
    public func generateAudio(text: String, voiceId: String, languageCode: String, instruct: String?) async throws -> Data
    public func generateAudio(context: GenerationContext, voiceId: String, languageCode: String) async throws -> Data
    public func generateProcessedAudio(text: String, voiceId: String, languageCode: String) async throws -> ProcessedAudio
    public func estimateDuration(text: String, voiceId: String) async -> TimeInterval
    public func isVoiceAvailable(voiceId: String) async -> Bool

    // VoxAlta-specific methods
    public func loadVoice(id: String, clonePromptData: Data, gender: String? = nil) async
    public func unloadVoice(id: String) async
    public func unloadAllVoices() async
}
```

#### Dual-Mode Routing

**Route 1 -- Preset speakers** (no clone prompt needed):
```swift
let audio = try await provider.generateAudio(text: "Hello", voiceId: "ryan", languageCode: "en")
```
Preset IDs: `ryan`, `aiden`, `vivian`, `serena`, `uncle_fu`, `dylan`, `eric`, `anna`, `sohee`

**Route 2 -- Clone prompts** (custom voices loaded via `loadVoice()`):
```swift
await provider.loadVoice(id: "ELENA", clonePromptData: lockData, gender: "female")
let audio = try await provider.generateAudio(text: "Hello", voiceId: "ELENA", languageCode: "en")
```

#### Preset Speaker Mapping

| User-facing name | CustomVoice speaker name | Notes |
|-----------------|------------------------|-------|
| `anna` | `ono_anna` | Only name that differs from its speaker ID |
| All others | Same as user name | `ryan` -> `"ryan"`, etc. |

#### Registration with SwiftHablare

```swift
let registry = VoiceProviderRegistry.shared
await registry.register(VoxAltaProviderDescriptor.descriptor())
```

### GenerationSettings

Controls sampling behavior for Qwen3-TTS audio generation.

```swift
public struct GenerationSettings: Codable, Sendable, Equatable {
    public let temperature: Float       // Default: 0.7 (0.3-0.5 stable, 0.8-1.0 expressive)
    public let topP: Float              // Default: 0.9 (nucleus sampling threshold)
    public let repetitionPenalty: Float  // Default: 1.3 (1.0 = none, 1.5+ = aggressive)
    public let maxTokens: Int           // Default: 16384 (~22 min audio at 12Hz token rate)

    // Auto-chunking (transparent, on by default)
    public let enableAutoChunking: Bool       // Default: true
    public let chunkTargetDuration: TimeInterval  // Default: 10.0 seconds
    public let chunkPauseDuration: TimeInterval   // Default: 0.25 seconds

    public static let `default` = GenerationSettings()
}
```

Passed to `VoiceLockManager.generateAudio()` and stored on `VoxAltaVoiceProvider`.

#### Auto-Sentence Chunking

When `enableAutoChunking` is `true` and a phrase's estimated duration exceeds `chunkTargetDuration`, `VoiceLockManager.generateAudio` splits the text at sentence boundaries (Foundation's ICU-backed `enumerateSubstrings(.bySentences)`), generates each chunk reusing the same voice clone prompt, and concatenates the results with `chunkPauseDuration` of silence between chunks. This defeats reference-anchor dilution ("TRIM ratio drift") in long ICL voice cloning generations, where the reference audio codes become a vanishing fraction of the model's context past ~10 seconds and prosody drifts away from the reference pattern.

Chunking is **transparent to callers** — same input, same output type, no API change. To opt out, pass `GenerationSettings(enableAutoChunking: false)`. Tune `chunkTargetDuration` lower (8.0s) for stronger anchors with more pauses, higher (12.0s) for fewer pauses with weaker anchors.

Tests: see `Tests/SwiftVoxAltaTests/VoiceLockManagerChunkingTests.swift` (21 cases covering passthrough, packing, ICU correctness on abbreviations/decimals/version-tokens/ellipses/em-dashes, silence array, and settings). Historical context lives in `docs/complete/SENTENCE_CHUNKING_DISCUSSION.md` and `docs/complete/FIXME-sentence-chunking.md`. The cross-package contract for GLOSA-AV is documented in `glosa-av/REQUIREMENTS.md` §4.8.

### GenerationContext

Envelope carrying a phrase and optional metadata through the TTS pipeline.

```swift
public struct GenerationContext: Codable, Sendable {
    public let phrase: String
    public let metadata: [String: AnyCodableValue]  // Keys normalized to snake_case

    public init(phrase: String, metadata: [String: AnyCodableValue] = [:])
    public init(phrase: String, instruct: String?, metadata: [String: AnyCodableValue] = [:])

    public var instruct: String?       // Extracted from metadata["instruct"]
    public var serializedSize: Int     // JSON byte count for logging
}
```

### VoiceLock

Locked voice identity for consistent TTS rendering. Created by extracting a clone prompt from audio provided by SwiftEchada (via `.vox` files).

```swift
public struct VoiceLock: Codable, Sendable {
    public let characterName: String
    public let clonePromptData: Data       // Serialized speaker embedding
    public let designInstruction: String
    public let lockedAt: Date
}
```

### VoiceLockManager

Enum namespace for clone prompt extraction and audio generation. **This is NOT voice creation** -- `createLock` extracts a clone prompt from audio that already exists (e.g., sample audio embedded in a `.vox` file by SwiftEchada). Voice creation happens upstream in SwiftEchada.

```swift
public enum VoiceLockManager: Sendable {
    // Extract a clone prompt from existing audio (NOT voice creation)
    // Used when switching models or re-extracting from .vox sample audio
    public static func createLock(
        characterName: String,
        candidateAudio: Data,         // WAV audio from .vox file or SwiftEchada output
        designInstruction: String,
        modelManager: VoxAltaModelManager,
        sampleSentence: String? = nil,
        modelRepo: Qwen3TTSModelRepo = .base1_7B
    ) async throws -> VoiceLock

    // Generate audio from GenerationContext envelope
    public static func generateAudio(
        context: GenerationContext,
        voiceLock: VoiceLock,
        language: String = "en",
        modelManager: VoxAltaModelManager,
        modelRepo: Qwen3TTSModelRepo = .base1_7B,
        cache: VoxAltaVoiceCache? = nil,
        settings: GenerationSettings = .default
    ) async throws -> Data

    // Generate audio from plain text
    public static func generateAudio(
        text: String,
        voiceLock: VoiceLock,
        language: String = "en",
        instruct: String? = nil,
        modelManager: VoxAltaModelManager,
        modelRepo: Qwen3TTSModelRepo = .base1_7B,
        cache: VoxAltaVoiceCache? = nil,
        settings: GenerationSettings = .default
    ) async throws -> Data
}
```

**Performance:**
- First generation: ~20-40s per line (includes clone prompt deserialization)
- Subsequent generations: ~10-20s per line (2x speedup via clone prompt caching in VoxAltaVoiceCache)

### VoxAltaVoiceCache

Actor-based thread-safe cache with two layers:

```swift
public actor VoxAltaVoiceCache {
    // Layer 1: Raw clone prompt data (serialized bytes)
    public struct CachedVoice: Sendable {
        public let clonePromptData: Data
        public let gender: String?
    }

    public func store(id: String, data: Data, gender: String?)
    public func remove(id: String)
    public func removeAll()                    // Clears both voice AND clone prompt caches
    public func get(id: String) -> CachedVoice?
    public func allVoiceIds() -> [String]
    public func allVoices() -> [(id: String, voice: CachedVoice)]
    public var count: Int

    // Layer 2: Deserialized clone prompts (avoids repeated deserialization)
    public func getClonePrompt(id: String) -> VoiceClonePrompt?
    public func storeClonePrompt(id: String, clonePrompt: VoiceClonePrompt)
}
```

### VoxAltaModelManager

Actor managing Qwen3-TTS model lifecycle.

```swift
public actor VoxAltaModelManager {
    public var isModelLoaded: Bool
    public var currentModelRepo: String?
    public var totalPhysicalMemory: UInt64
    public var availableMemory: UInt64

    public func loadModel(repo: String) async throws -> any SpeechGenerationModel
    public func loadModel(_ modelRepo: Qwen3TTSModelRepo) async throws -> any SpeechGenerationModel
    public func unloadModel()
    public func migrateIfNeeded()                          // Legacy -> Acervo migration
    public nonisolated func isModelInAcervo(_ modelId: String) -> Bool
    public func checkMemory(forModelSizeBytes: Int) -> Bool   // Warning only, non-blocking
    public func validateMemory(forModelSizeBytes: Int) throws // Hard gate
}
```

### Qwen3TTSModelRepo

```swift
public enum Qwen3TTSModelRepo: String, CaseIterable, Sendable {
    case voiceDesign1_7B  // mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16  (~4.2GB, used by SwiftEchada)
    case base1_7B         // mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16         (~4.3GB)
    case base0_6B         // mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16         (~2.4GB)
    case customVoice1_7B  // mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16  (~4.3GB)
    case customVoice0_6B  // mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16  (~2.4GB)
    case base1_7B_8bit    // mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit         (~1.7GB)
    case base1_7B_4bit    // mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit         (~850MB, NOT recommended)

    public var slug: String              // "0.6b" or "1.7b"
    public var displayName: String
    public static let supportedSlugs: Set<String> = ["0.6b", "1.7b"]
    public init?(slug: String)           // Resolves to default Base model for that size
}
```

### VoxImporter / VoxExporter

```swift
// Import
public struct VoxImportResult: Sendable {
    public let name: String
    public let description: String
    public let method: String?               // "designed", "synthesized", "cloned", "preset", "hybrid"
    public let clonePromptData: Data?        // Model-aware lookup
    public let sampleAudioData: Data?
    public let referenceAudio: [String: Data]
    public let createdAt: Date
    public let manifest: VoxManifest
    public let supportedModels: [String]     // e.g. ["1.7b", "0.6b"]
}

public enum VoxImporter: Sendable {
    public static func importVox(from url: URL, modelQuery: String = "1.7b") throws -> VoxImportResult
}

// Export
public enum VoxExporter: Sendable {
    public static func addClonePrompt(to vox: VoxFile, data: Data, modelRepo: Qwen3TTSModelRepo = .base1_7B) throws
    public static func addSampleAudio(to vox: VoxFile, data: Data, modelRepo: Qwen3TTSModelRepo = .base1_7B) throws
    public static func updateClonePrompt(in voxURL: URL, clonePromptData: Data, modelRepo: Qwen3TTSModelRepo = .base1_7B) throws
    public static func updateSampleAudio(in voxURL: URL, sampleAudioData: Data, modelRepo: Qwen3TTSModelRepo = .base1_7B) throws
    public static func modelSizeSlug(for repo: Qwen3TTSModelRepo) -> String
}
```

### AudioConversion

```swift
public enum AudioConversion: Sendable {
    public static func mlxArrayToWAVData(_ audio: MLXArray, sampleRate: Int = 24000) throws -> Data
    public static func wavDataToMLXArray(_ data: Data) throws -> MLXArray
}
```

### VoxAltaError

```swift
public enum VoxAltaError: Error, LocalizedError, Sendable {
    case cloningFailed(String)
    case modelNotAvailable(String)
    case voiceNotLoaded(String)
    case insufficientMemory(available: Int, required: Int)
    case audioExportFailed(String)
    case voxExportFailed(String)
    case voxImportFailed(String)
}
```

### AppleSiliconGeneration

21 cases: m1, m1Pro, m1Max, m1Ultra, m2, m2Pro, m2Max, m2Ultra, m3, m3Pro, m3Max, m3Ultra, m4, m4Pro, m4Max, m4Ultra, m5, m5Pro, m5Max, m5Ultra, unknown.

```swift
public enum AppleSiliconGeneration: String, Sendable, CaseIterable {
    public var hasNeuralAccelerators: Bool   // true for M5 variants only
    public static var current: AppleSiliconGeneration  // Cached, detected via sysctlbyname
}
```

---

## Telemetry

SwiftVoxAlta provides a pluggable telemetry pipeline so that consumers (Produciesta and others) can observe model load/unload events and voice-cache growth in production without coupling to internal implementation details. The public contract consists of five types: `VoxAltaTelemetryEvent` (six-case enum covering model and cache lifecycle), `VoxAltaTelemetryReporter` (async `Sendable` protocol consumers implement), `VoiceCacheTelemetry` and `MLXRetentionReport` (value snapshots carried by events), and `getCurrentProcessMemory()` (process RSS in MB for delta measurements). Attach a reporter via `await provider.setTelemetry(reporter)` and detach with `nil`; a nil reporter is always a no-op. An empirical 3-cycle preflight probe (`Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift`) established a **NO LEAK** verdict for `unloadModel()` — marginal residual of ~12 MB per cycle (well below the 50 MB threshold), confirming the ~340 MB first-cycle residual is one-time MLX/Metal framework overhead, not a progressive leak. See [`docs/telemetry.md`](docs/telemetry.md) for the full API reference, Produciesta integration example, preflight probe results, and known limitations.

---

## CLI Tool (`diga`)

Drop-in replacement for `/usr/bin/say` with neural TTS.

### Usage

```bash
diga "Hello, world!"                    # Play through speakers
diga -f input.txt                       # Read from file
echo "Hello" | diga                     # Read from stdin
diga -o output.wav "Hello"              # Write WAV file
diga -o output.m4a "Hello"              # Write AAC file
diga -o output.aiff "Hello"             # Write AIFF file
diga -v elena "Hello"                   # Use specific voice
diga -v voice.vox "Hello"              # Synthesize directly from .vox file
diga --instruct "whisper" "Hello"       # Performance direction
diga --voices                           # List all voices
diga -v ?                               # List all voices (shorthand)
diga --import-vox voice.vox             # Import voice from .vox file
diga --model 0.6b "Hello"              # Override model (smaller, faster)
diga --model 1.7b "Hello"              # Override model (larger, better quality)
```

### CLI Flags

| Flag | Short | Purpose |
|------|-------|---------|
| `--voices` | | List all available voices |
| `--voice <name>` | `-v` | Select voice (name or .vox file path) |
| `--import-vox <file>` | | Import voice from a `.vox` file |
| `--output <path>` | `-o` | Write to file (WAV/AIFF/M4A) |
| `--file <path>` | `-f` | Read input from file (`-` for stdin) |
| `--file-format <fmt>` | | Override output format (wav, aiff, m4a) |
| `--instruct <text>` | | Performance direction (e.g., "speak softly") |
| `--model <id>` | | Override model (0.6b, 1.7b, or HuggingFace repo) |
| `--version` | | Show version |
| `--help` | `-h` | Show help |

### Parenthetical-to-Instruct Mapping

Screenplay parentheticals map directly to `instruct` values. Strip enclosing parentheses, pass inner text verbatim:
- `(softly)` -> `"softly"`
- `(angry)` -> `"angry"`
- `(with a French accent)` -> `"with a French accent"`
- `(hushed, conspiratorial)` -> `"hushed, conspiratorial"`

The `instruct` parameter is per-phrase and conditions audio generation suggestively.

### CLI Internal Types (diga target, not public API)

| Type | Purpose |
|------|---------|
| `DigaEngine` (actor) | Orchestrates model loading, voice resolution, chunked synthesis |
| `VoiceStore` (struct) | JSON-based voice registry at `~/.diga/voices/index.json` |
| `StoredVoice` (struct) | Voice entry: name, type, designDescription, clonePromptPath, createdAt |
| `VoiceType` (enum) | `.builtin`, `.designed`, `.cloned`, `.preset` |
| `BuiltinVoices` (enum) | 9 preset speaker definitions |
| `TextChunker` (enum) | Sentence-boundary splitting via `NLTokenizer` (200 words/chunk default) |
| `WAVConcatenator` (enum) | Concatenate multiple WAV segments into single output |
| `AudioPlayback` (class) | AVAudioEngine-based speaker output + streaming chunked playback |
| `AudioFileWriter` (enum) | Write WAV/AIFF/M4A files (AIFF via AudioFile API, M4A via ExtAudioFile) |
| `AudioFormat` (enum) | `.wav`, `.aiff`, `.m4a` with extension inference |
| `DigaEngineError` (enum) | `.voiceNotFound`, `.voiceDesignFailed`, `.synthesisFailed`, `.wavConcatenationFailed`, `.modelNotAvailable` |

---

## Clone Prompt Resolution (DigaEngine)

When synthesizing with an existing voice (`diga "Hello" -v alice`), `DigaEngine.loadOrCreateClonePrompt()` checks five sources in order. **VoxAlta never creates a voice from scratch** -- it only resolves clone prompts that were originally created by SwiftEchada and packaged in `.vox` files.

```
1. Memory cache: cachedClonePrompts["alice:1.7b"]       -> HIT? use it
2. Disk cache: ~/.diga/voices/alice-1.7b.cloneprompt     -> HIT? use it, cache in memory
3. Legacy disk: ~/.diga/voices/alice.cloneprompt          -> HIT? use it (1.7b only), migrate
4. .vox re-extraction: alice.vox -> sample audio or ref audio -> re-extract clone prompt for current model
   (This is re-extraction for a different model size, not voice creation)
5. Error: "No clone prompt found. Use `echada cast` to create one, then --import-vox."
```

Steps 2-4 also update the `.vox` file with the clone prompt if present on disk.

---

## Synthesis Flow

VoxAlta consumes `.vox` files produced by SwiftEchada and renders speech:

```
.vox file (from echada cast) -> VoxImporter -> clone prompt Data
Text -> TextChunker.chunk() -> ["sentence 1", "sentence 2", ...]

For each chunk:
  VoiceLockManager.generateAudio()
    -> check VoxAltaVoiceCache for deserialized clone prompt (Layer 2)
    -> cache MISS: VoiceClonePrompt.deserialize() -> store in cache
    -> Qwen3TTSModel.generateWithClonePrompt(text, prompt, instruct, settings)
    -> MLXArray -> AudioConversion.mlxArrayToWAVData() -> WAV segment
    -> Stream.defaultStream(.gpu).synchronize() + Memory.clearCache()

WAVConcatenator.concatenate(segments) -> final WAV

Output:
  -o file.wav  -> AudioFileWriter (wav/aiff/m4a)
  (default)    -> AudioPlayback (speakers)
```

---

## VoxFormat (.vox) Integration

### Embedding Paths

| Path | Purpose |
|------|---------|
| `embeddings/qwen3-tts/{size}/clone-prompt.bin` | Model-specific clone prompt (e.g., `1.7b/`, `0.6b/`) |
| `embeddings/qwen3-tts/{size}/sample-audio.wav` | Model-specific engine-generated voice sample |
| `reference/` | Optional reference audio files |
| `manifest.json` | Voice metadata (name, description, provenance) |

### CLI Usage

```bash
diga --import-vox voice.vox            # Import to ~/.diga/voices/
diga -v voice.vox "Hello, world!"      # Synthesize directly (no import needed)
```

---

## Disk Layout

```
~/.diga/voices/
├── index.json                    # Voice registry (JSON array of StoredVoice)
├── alice-1.7b.cloneprompt        # Model-specific serialized speaker embedding (~5-10KB)
├── alice.cloneprompt             # Legacy (treated as 1.7b only)
└── alice.vox                     # Portable container (ZIP)
    ├── manifest.json
    ├── reference/                # (optional reference audio)
    └── embeddings/qwen3-tts/
        ├── 1.7b/clone-prompt.bin
        ├── 0.6b/clone-prompt.bin # (optional second model)
        └── 1.7b/sample-audio.wav # Engine-generated voice sample

~/Library/SharedModels/           # Model weights (shared via SwiftAcervo)
├── mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16/         (~4.3GB)
├── mlx-community_Qwen3-TTS-12Hz-0.6B-Base-bf16/         (~2.4GB)
└── mlx-community_Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16/  (~4.3GB, preset speakers)
```

### App Group / ACERVO_APP_GROUP_ID (REQUIRED for all integrators)

The `~/Library/SharedModels/` path above is the App Group container `group.intrusive-memory.models`. SwiftAcervo v0.10.0 resolves its App Group ID in this order: `ACERVO_APP_GROUP_ID` env var → `com.apple.security.application-groups` entitlement (macOS only) → `fatalError`. **There is no silent fallback.** If neither source is configured, `Acervo.sharedModelsDirectory` calls `fatalError` and the process traps immediately.

#### Signed UI apps (macOS / iOS)

Every app target that links SwiftVoxAlta (or any SwiftAcervo consumer) must enable the App Group capability:

1. Target → **Signing & Capabilities** → **+ Capability** → **App Groups**.
2. Check or add `group.intrusive-memory.models`.
3. Rebuild.

iOS apps additionally need `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the launch environment (the entitlement alone is not sufficient on iOS).

Verify at runtime by printing `Acervo.sharedModelsDirectory`. A correctly entitled app shows a path under `~/Library/Group Containers/group.intrusive-memory.models/...`.

#### CLI tools, scripts, CI jobs, test runners

Unsigned binaries (including the `diga` CLI in this repo), scripts, CI jobs, and Swift test runners cannot join an App Group via entitlement. These processes must export `ACERVO_APP_GROUP_ID` instead:

```sh
export ACERVO_APP_GROUP_ID=group.intrusive-memory.models
```

The standard place for developer machines is `~/.zprofile`. For CI, set it as a job-level environment variable. Without this export, `diga` and any test that exercises a SwiftAcervo path will trap with `fatalError` at the point `Acervo.sharedModelsDirectory` is first accessed.

See [SwiftAcervo USAGE.md](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) for the full integration checklist.

---

## Design Patterns

- **VoiceProvider abstraction** -- Implements SwiftHablare's protocol for plug-and-play integration
- **Actor isolation** -- `VoxAltaModelManager` and `VoxAltaVoiceCache` are actors for thread safety; `DigaEngine` is also an actor
- **Two-layer clone prompt cache** -- Layer 1: raw `Data` in `VoxAltaVoiceCache.voices`; Layer 2: deserialized `VoiceClonePrompt` in `clonePromptCache`
- **Lazy model loading** -- Models loaded on-demand, cached, auto-unloaded on model switch
- **Memory-aware loading** -- Warns on low memory (non-blocking); macOS manages swap
- **GPU state cleanup** -- `Stream.defaultStream(.gpu).synchronize()` + `Memory.clearCache()` after every generation to prevent stale Metal buffers
- **Container-first .vox API** -- `VoxFile(contentsOf:)` + `add()` + `write(to:)` for all .vox operations
- **Strict concurrency** -- Swift 6 language mode with `StrictConcurrency` enabled

---

## Testing

### Test Structure

- **SwiftVoxAltaTests/** (13 files): VoiceProvider, model manager, voice cache, error paths, audio conversion, voice lock, VoxImporter/VoxExporter, generation context, generation settings, consistency, Apple Silicon info, type tests
- **DigaTests/** (11 files): CLI integration, audio file writer, audio playback, engine, model manager, voice store, version, release, vox integration, dual model
- **~328 tests** across 24 test files using Swift Testing `@Test` macro

### Running Tests

```bash
make test-unit            # Fast: all unit tests (~5-10 seconds)
make test-integration     # Slow: requires binary + cached voices
make test                 # Both
```

### CI Behavior

On CI (`GITHUB_ACTIONS` set):
- `SwiftVoxAltaTests` are **skipped** (Metal compiler on GitHub runners doesn't support MLX features)
- Only `DigaTests` run, excluding `DigaBinaryIntegrationTests` and `DigaDualModelIntegrationTests`
- Integration tests commented out entirely in `.github/workflows/tests.yml`

---

## Development Workflow

- **Branch**: `development` -> PR -> `main`
- **Never commit directly to `main`**
- **CI Required**: Unit tests must pass before merge

## Release Process

1. Bump version in `Sources/diga/Version.swift` and `VoxAltaVoiceProvider.swift`
2. Tag on `main` (e.g., `v0.9.5`)
3. GitHub Release triggers `.github/workflows/release.yml`
4. Release workflow: `make release` -> tarball (`diga-{version}-arm64-macos.tar.gz`) -> upload assets -> dispatch to `intrusive-memory/homebrew-tap`
5. Homebrew tap auto-updates formula with new URL and SHA256

---

## Recent Changes

### v0.10.1

- **docs**: Rewrite `ARCHITECTURE.md` and trim `ACERVO_AUDIT.md` to reflect current architecture and Acervo v2 reality
- **docs**: Audit hygiene cleanup; move Character Studio out of VoxAlta scope (lives in SwiftEchada)
- **chore**: Bump library version to 0.10.1

### v0.10.0

- **chore**: Adopt sibling dependency pattern for intrusive-memory/* deps; bump intrusive-memory dependency versions
- **test**: Add Diga binary integration suite (`DigaBinaryIntegrationTests`); delegate model paths to SwiftAcervo
- **ci**: Exclude `DigaBinaryIntegrationTests` from `test-unit` (binary/model not provisioned on CI runners)
- **docs**: Stop hardcoding model cache paths in active docs; defer to `Acervo.sharedModelsDirectory`

### v0.9.9

- **feat**: Adopt SwiftAcervo v2 `withComponentAccess` for validated model loading
- **refactor**: Manifest-first `ComponentDescriptor` model registration
- **ci**: Standardized R2 CDN upload workflow for all 7 Qwen3-TTS models
- **test**: Replace download-workflow tests with focused registration tests; CDN availability is SwiftAcervo's concern
- **fix**: Restore mlx-audio-swift to git URL dependency so CI resolves cleanly

### v0.9.7

- **fix**: Replace tokenizer.json with vocab.json in required files list
- Qwen3-TTS models use BPE tokenizer format (vocab.json + merges.txt), not tokenizer.json
- Fixes fileNotInManifest errors on every voice generation attempt

### v0.9.6

- Bump SwiftTuberia dependency to 0.2.6

### v0.9.5

- Bumped SwiftTuberia dependency to 0.2.7

### v0.9.4

- Bumped SwiftTuberia minimum dependency from 0.2.0 to 0.2.6
- SwiftTuberia 0.2.6 fixes the compiled silu op in the SDXL VAE decoder (replaces `MLXNN.silu()` with `h * MLX.sigmoid(h)`)

---

## Documentation Index

| Document | Purpose |
|----------|---------|
| [AGENTS.md](AGENTS.md) | This file -- complete project documentation |
| [CLAUDE.md](CLAUDE.md) | Claude Code-specific build instructions |
| [GEMINI.md](GEMINI.md) | Gemini-specific instructions |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [docs/OVERVIEW.md](docs/OVERVIEW.md) | High-level project overview |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture and design decisions |
| [docs/API-SURFACE.md](docs/API-SURFACE.md) | API surface reference |
| [docs/AVAILABLE_VOICES.md](docs/AVAILABLE_VOICES.md) | Built-in voices with descriptions |
| [docs/BUILDING.md](docs/BUILDING.md) | Build from source, test suites |
| [docs/CLI.md](docs/CLI.md) | CLI usage and voice management |
| [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md) | Open design questions |
| [docs/PRODUCIESTA_INTEGRATION.md](docs/PRODUCIESTA_INTEGRATION.md) | Integration with Produciesta app |
