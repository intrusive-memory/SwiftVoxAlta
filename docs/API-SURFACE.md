# API Surface

## Design Philosophy

Mirror SwiftBruja's progressive disclosure:
- Simple case: one line to render a script
- Medium case: configure models and output format
- Advanced case: control the full pipeline (parse, profile, design, render)

## Public API

### Top-Level Facade

```swift
import SwiftVoxAlta

// Simplest possible usage -- render an entire script
let output = try await VoxAlta.render("path/to/script.fountain")

// Specify output directory
let output = try await VoxAlta.render(
    "path/to/script.fountain",
    outputDir: "path/to/output/"
)

// Render with a callback for voice audition
let output = try await VoxAlta.render(
    "path/to/script.fountain",
    onAudition: { character, candidates in
        // Present candidates to user, return selected index
        return selectedIndex
    }
)
```

### Character Studio API

```swift
// Parse a script
let script = try VoxAlta.parse("path/to/script.fountain")

// Analyze characters (LLM pass via SwiftBruja)
let profiles = try await VoxAlta.analyzeCharacters(in: script)

// Design a voice from a profile
let candidates = try await VoxAlta.designVoice(
    for: profiles["ELENA"]!,
    candidateCount: 5
)

// Lock a voice
let voiceLock = try await VoxAlta.lockVoice(
    for: "ELENA",
    referenceClip: candidates[2]  // user's selection
)

// Render all lines for a character
let lines = try await VoxAlta.renderLines(
    for: "ELENA",
    in: script,
    voice: voiceLock
)
```

### Render Output

```swift
/// Result of rendering a full script
public struct RenderOutput: Codable, Sendable {
    /// Per-character rendered lines
    public let characters: [String: CharacterOutput]
    /// Total render duration
    public let durationSeconds: Double
    /// Output directory path
    public let outputPath: String
}

/// All rendered audio for one character
public struct CharacterOutput: Codable, Sendable {
    /// Character name
    public let name: String
    /// Voice profile used
    public let profile: CharacterProfile
    /// Rendered lines in script order
    public let lines: [RenderedLine]
    /// Path to concatenated character track (all lines joined)
    public let trackPath: String
}

/// A single rendered line of dialogue
public struct RenderedLine: Codable, Sendable {
    /// Original dialogue text
    public let text: String
    /// Parenthetical direction, if any
    public let parenthetical: String?
    /// Scene context
    public let sceneHeading: String
    /// Path to rendered WAV file
    public let audioPath: String
    /// Duration of the audio in seconds
    public let audioDurationSeconds: Double
    /// Line position in the script
    public let scriptOrder: Int
}
```

### Character Profile Types

```swift
/// Profile derived from script analysis
public struct CharacterProfile: Codable, Sendable {
    public let name: String
    public let gender: Gender
    public let ageRange: String
    public let description: String
    public let voiceTraits: [String]
    public let summary: String
    /// Number of dialogue lines in the script
    public let lineCount: Int
    /// Scenes the character appears in
    public let scenes: [String]
}

public enum Gender: String, Codable, Sendable {
    case male
    case female
    case nonBinary
    case unspecified
}
```

### Voice Management

```swift
/// A locked voice identity for a character
public struct VoiceLock: Codable, Sendable {
    public let characterName: String
    /// Path to the reference audio clip
    public let referenceClipPath: String
    /// Path to the pre-computed clone prompt
    public let clonePromptPath: String
    /// The instruction text that generated this voice
    public let designInstruction: String
    /// When the voice was locked
    public let lockedAt: Date
}

// Voice management
let lock = try await VoxAlta.lockVoice(for:referenceClip:)
let lock = try VoxAlta.loadVoiceLock(for: "ELENA", project: projectId)
let isStale = try await VoxAlta.checkVoiceStaleness(lock, against: updatedProfile)
```

### Configuration

```swift
/// Configuration for a render pass
public struct VoxAltaConfig: Codable, Sendable {
    /// TTS model for voice design (default: VoiceDesign 1.7B)
    public var designModel: String
    /// TTS model for line rendering (default: Base 1.7B)
    public var renderModel: String
    /// LLM model for character analysis (default: SwiftBruja default)
    public var analysisModel: String
    /// Number of voice candidates to generate per character
    public var candidateCount: Int
    /// Output audio format
    public var outputFormat: AudioFormat
    /// Whether to generate concatenated per-character tracks
    public var generateTracks: Bool
    /// Whether to include parentheticals as render hints
    public var useParentheticalsAsHints: Bool

    public static let `default` = VoxAltaConfig(...)
}

public enum AudioFormat: String, Codable, Sendable {
    case wav
    case aiff
    case m4a
}
```

## CLI

```
USAGE: voxalta <command> [options]

COMMANDS:
  render      Render a script to audio
  parse       Parse a script and show structure
  analyze     Analyze characters in a script
  design      Design voices for characters
  audition    Generate and preview voice candidates
  lock        Lock a selected voice for a character
  voices      List locked voices for a project
  models      List downloaded TTS models
  download    Download a TTS model

EXAMPLES:
  voxalta render script.fountain
  voxalta render script.fountain --output ./audio/
  voxalta analyze script.fountain --character ELENA
  voxalta design script.fountain --character ELENA --candidates 5
  voxalta audition script.fountain --character ELENA
  voxalta lock script.fountain --character ELENA --candidate 2
  voxalta render script.fountain --characters ELENA,MARCUS
```

## Error Types

```swift
public enum VoxAltaError: Error, LocalizedError, Sendable {
    case scriptParsingFailed(String)
    case characterNotFound(String)
    case profileAnalysisFailed(String, Error)
    case voiceDesignFailed(String, Error)
    case voiceNotLocked(String)
    case renderFailed(String, Error)
    case modelNotAvailable(String)
    case insufficientMemory(available: Int64, required: Int64)
    case audioExportFailed(String, Error)
    case staleVoiceLock(String)
}
```
