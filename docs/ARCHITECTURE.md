# Architecture

## Package Structure

```
SwiftVoxAlta/
├── Package.swift
├── Sources/
│   ├── SwiftVoxAlta/          # Library target
│   │   ├── Core/
│   │   │   ├── VoxAlta.swift              # Public facade
│   │   │   ├── VoxAltaModelManager.swift  # TTS model lifecycle (actor)
│   │   │   ├── VoxAltaMemory.swift        # Memory validation
│   │   │   ├── VoxAltaTypes.swift         # Public data types
│   │   │   └── VoxAltaError.swift         # Error types
│   │   ├── Script/
│   │   │   ├── FountainParser.swift        # Fountain format parser
│   │   │   ├── ScriptTypes.swift           # Script data model
│   │   │   └── CharacterExtractor.swift    # Pull character data from parsed script
│   │   ├── Studio/
│   │   │   ├── CharacterAnalyzer.swift     # LLM-based profile generation
│   │   │   ├── VoiceDesigner.swift         # Qwen3-TTS VoiceDesign wrapper
│   │   │   ├── VoiceAuditioner.swift       # Candidate generation + selection
│   │   │   ├── VoiceLockManager.swift      # Persistence of locked voices (actor)
│   │   │   └── StudioTypes.swift           # CharacterProfile, VoiceLock, etc.
│   │   └── Render/
│   │       ├── LineRenderer.swift          # Per-line TTS via voice cloning
│   │       ├── TrackAssembler.swift        # Concatenate lines into tracks
│   │       ├── AudioExporter.swift         # Format conversion (WAV/AIFF/M4A)
│   │       └── RenderTypes.swift           # RenderOutput, RenderedLine, etc.
│   └── voxalta/                # CLI target
│       └── VoxAltaCLI.swift
├── Tests/
│   ├── SwiftVoxAltaTests/
│   │   ├── FountainParserTests.swift
│   │   ├── CharacterExtractorTests.swift
│   │   ├── CharacterAnalyzerTests.swift
│   │   ├── VoiceDesignerTests.swift
│   │   ├── LineRendererTests.swift
│   │   ├── MemoryTests.swift
│   │   └── TypeTests.swift
│   └── VoxAltaIntegrationTests/
│       ├── FullPipelineTests.swift
│       └── CLITests.swift
└── docs/
```

## Component Responsibilities

### Core Layer

**VoxAlta.swift** -- The public facade. All public methods are static, delegating to internal managers. Mirrors SwiftBruja's `Bruja` enum pattern.

**VoxAltaModelManager.swift** -- Actor managing TTS model downloads, loading, and caching. Stores models under `~/Library/Caches/intrusive-memory/Models/TTS/`. Handles both VoiceDesign and Base model variants. Shares the download pipeline pattern with SwiftBruja's BrujaModelManager.

**VoxAltaMemory.swift** -- Memory validation before model loads. TTS has different memory characteristics than LLM inference (potentially two models loaded simultaneously during design + render phases), so thresholds are calibrated accordingly.

### Script Layer

**FountainParser.swift** -- Deterministic parser for Fountain screenplay format. No ML involved. Produces structured representations of scenes, characters, dialogue, action, and parentheticals.

This is a self-contained module. If a suitable Swift Fountain parser library exists and is maintained, we could depend on it instead. If not, we write our own -- Fountain is a well-specified format and parsers are straightforward.

**CharacterExtractor.swift** -- Walks parsed script data and collects all evidence for each character: their dialogue lines, parentheticals, action lines that mention them, scene headings for scenes they appear in, and any character description blocks.

### Studio Layer

**CharacterAnalyzer.swift** -- Calls SwiftBruja to run an LLM analysis of the extracted character evidence. Produces a `CharacterProfile` with voice-relevant descriptive fields. The LLM prompt is tightly scoped: derive traits from what's written, do not invent.

**VoiceDesigner.swift** -- Wraps Qwen3-TTS VoiceDesign. Takes a `CharacterProfile` and composes a natural language voice description, then generates audio.

**VoiceAuditioner.swift** -- Generates multiple voice candidates and manages the selection flow. Provides a callback-based API for UI integration and a CLI-based audition for terminal use.

**VoiceLockManager.swift** -- Actor that persists and retrieves voice locks. Manages the per-project directory structure. Handles staleness detection (has the character's profile changed enough to warrant re-audition?).

### Render Layer

**LineRenderer.swift** -- The workhorse. Takes a locked voice and a list of dialogue lines, renders each via Qwen3-TTS Base model voice cloning. Handles parenthetical hints (optional). Supports batch rendering with progress callbacks.

**TrackAssembler.swift** -- Concatenates rendered lines into per-character audio tracks in script order. Inserts configurable silence between lines.

**AudioExporter.swift** -- Format conversion using AVFoundation. WAV is native; AIFF and M4A are converted from the 24kHz WAV output.

## Dependency Graph

```
                    SwiftVoxAlta
                    /          \
              SwiftBruja    mlx-audio-swift
              /        \         |
         mlx-swift   swift-transformers
                        |
                   HuggingFace Hub
```

**Direct dependencies:**
- `SwiftBruja` -- LLM inference for character analysis
- `mlx-audio-swift` -- Qwen3-TTS inference on Apple Silicon
- `swift-argument-parser` -- CLI

**Transitive (via SwiftBruja):**
- `mlx-swift`, `mlx-swift-lm`, `swift-transformers`

**System frameworks:**
- `AVFoundation` -- Audio format conversion and playback
- `Foundation` -- File I/O, JSON, dates

## Concurrency Model

```
Main API (VoxAlta)
    |
    |-- VoxAltaModelManager (actor) -- thread-safe model cache
    |-- VoiceLockManager (actor) -- thread-safe voice persistence
    |
    |-- CharacterAnalyzer -- async, calls SwiftBruja
    |-- VoiceDesigner -- async, calls mlx-audio-swift
    |-- LineRenderer -- async, calls mlx-audio-swift
    |       |
    |       |-- Can render multiple characters concurrently
    |       |-- Lines within a character render sequentially
    |       |   (model generates one at a time)
    |
    |-- TrackAssembler -- sync, operates on files
    |-- AudioExporter -- async (AVFoundation)
```

Characters can be rendered in parallel if memory allows (each needs the Base model loaded, but they share the same model instance with different clone prompts). Lines within a character are sequential because the TTS model processes one utterance at a time.

## Data Flow

```
                    Fountain File
                         |
                    [FountainParser]
                         |
                    ParsedScript
                         |
                  [CharacterExtractor]
                         |
              CharacterEvidence (per character)
                         |
                  [CharacterAnalyzer]  <-- SwiftBruja LLM
                         |
                  CharacterProfile
                         |
                   [VoiceDesigner]  <-- Qwen3-TTS VoiceDesign
                         |
                  VoiceCandidates[]
                         |
                  [VoiceAuditioner]  <-- User selection
                         |
                     VoiceLock
                         |
                   [LineRenderer]  <-- Qwen3-TTS Base
                         |
                   RenderedLine[]
                         |
                  [TrackAssembler]
                         |
                  CharacterOutput
                         |
                  [AudioExporter]
                         |
                   Final Audio Files
```
