# VoiceDesign Character Voice Pipeline

VoxAlta provides a complete character voice pipeline for designing custom voices from character profiles using Qwen3-TTS VoiceDesign technology.

## Pipeline Overview

The VoiceDesign pipeline follows these steps:

1. **Character Analysis** - Extract character traits from screenplay evidence
2. **Voice Description** - Compose text description from character profile
3. **Candidate Generation** - Generate 3 voice candidates with VoiceDesign model
4. **Voice Locking** - Create clone prompt from selected candidate
5. **Audio Generation** - Render dialogue using locked voice identity

## Complete Workflow Example

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

## Model Requirements

The VoiceDesign pipeline requires two Qwen3-TTS models:

| Model | Size | Purpose | Download |
|-------|------|---------|----------|
| VoiceDesign 1.7B | 4.2 GB | Generate voice candidates from text descriptions | Auto-downloaded on first use |
| Base 1.7B | 4.3 GB | Clone voices and render dialogue from clone prompts | Auto-downloaded on first use |

**Total disk space**: ~8.5 GB (models cached at `~/Library/SharedModels/`)

Models are downloaded automatically from HuggingFace on first use via SwiftAcervo.

## Character Profile Structure

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

## Voice Lock Persistence

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

## Troubleshooting

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
