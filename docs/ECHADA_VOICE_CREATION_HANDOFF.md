# Voice Creation Code Handoff: VoxAlta -> SwiftEchada

## Why This Code Was Removed

This code was removed from SwiftVoxAlta because voice creation (analyzing screenplay characters and designing TTS voices) is a **casting** concern, not a **synthesis** concern. VoxAlta is a voice synthesis library -- it takes an already-designed voice and generates speech audio. The process of *creating* voices from screenplay analysis belongs in SwiftEchada's `echada cast` command, which orchestrates the full casting pipeline: extract character evidence, analyze via LLM, design voices, and store them for later synthesis.

All seven files below were part of VoxAlta and should be adapted into SwiftEchada with minimal changes. The main integration points are the dependencies listed below.

---

## Dependencies

| Dependency | What It Provides | Used By |
|---|---|---|
| **SwiftBruja** | `Bruja.query()` for on-device LLM inference (structured JSON output and plain text) | CharacterAnalyzer, SampleSentenceGenerator, ParentheticalMapper |
| **SwiftCompartido** | `GuionElementProtocol` (screenplay element types: `.character`, `.dialogue`, `.parenthetical`, `.sceneHeading`, `.action`) | CharacterEvidenceExtractor |
| **MLXAudioTTS** | `Qwen3TTSModel`, `GenerateParameters`, `MLXArray` for Qwen3-TTS VoiceDesign generation | VoiceDesigner |

---

## Pipeline Overview

The voice creation pipeline flows through these stages:

1. **CharacterEvidenceExtractor** walks an array of `GuionElementProtocol` elements (from SwiftCompartido) and collects raw evidence per character: dialogue lines, parentheticals, scene headings, and action mentions. Pure logic, no async, no model needed.

2. **CharacterAnalyzer** takes a `CharacterEvidence` struct and sends it to an on-device LLM via SwiftBruja. The LLM returns a structured JSON `CharacterProfile` containing gender, age range, voice traits, and a prose voice summary.

3. **SampleSentenceGenerator** takes a `CharacterProfile` (or a freeform voice description) and asks the LLM to write a single natural sentence that character would say. This sentence is used for voice audition instead of a generic "hello" sample.

4. **VoiceDesigner** composes a Qwen3-TTS VoiceDesign description string from a `CharacterProfile`, then calls the VoiceDesign model to generate candidate WAV audio. Multiple candidates can be generated in parallel (via `TaskGroup`) since sampling stochasticity produces variation.

5. **ParentheticalMapper** translates screenplay parentheticals (e.g., `(whispering)`, `(angrily)`) into Qwen3-TTS instruct strings for runtime speech modulation. Uses a static lookup table for common entries and falls back to LLM classification for unknown parentheticals.

6. **ReferenceAudioGenerator** is a macOS-only fallback that uses the `say` command to produce reference audio for voice cloning when VoiceDesign is unavailable or too slow.

---

## Source Files

### 1. CharacterProfile.swift

Data types for character evidence and analyzed profiles. These are the shared currency between the extractor, analyzer, and voice designer. `CharacterEvidence` is the input (raw screenplay data); `CharacterProfile` is the output (LLM-analyzed voice characteristics).

```swift
//
//  CharacterProfile.swift
//  SwiftVoxAlta
//
//  Types representing analyzed character voice profiles and evidence extracted from screenplays.
//

import Foundation

/// Gender classification for a character, used for voice design targeting.
public enum Gender: String, Codable, Sendable {
    case male
    case female
    case nonBinary
    case unknown
}

/// An analyzed character profile derived from screenplay evidence, suitable for voice design.
///
/// `CharacterProfile` is the output of character analysis (via SwiftBruja LLM inference).
/// It contains the information needed to compose a Qwen3-TTS VoiceDesign description
/// that will generate a matching voice.
public struct CharacterProfile: Codable, Sendable {
    /// The character's name (normalized to uppercase).
    public let name: String

    /// The inferred gender of the character.
    public let gender: Gender

    /// A textual description of the character's approximate age range (e.g., "30s", "elderly", "young adult").
    public let ageRange: String

    /// A prose description of the character's personality and vocal qualities.
    public let description: String

    /// Specific voice traits inferred from dialogue and parentheticals
    /// (e.g., "gravelly", "warm", "clipped speech", "southern drawl").
    public let voiceTraits: [String]

    /// A concise summary combining all profile attributes, suitable for direct use
    /// as a Qwen3-TTS VoiceDesign prompt input.
    public let summary: String

    public init(
        name: String,
        gender: Gender,
        ageRange: String,
        description: String,
        voiceTraits: [String],
        summary: String
    ) {
        self.name = name
        self.gender = gender
        self.ageRange = ageRange
        self.description = description
        self.voiceTraits = voiceTraits
        self.summary = summary
    }
}

/// Raw evidence extracted from a screenplay for a single character.
///
/// `CharacterEvidence` collects all dialogue lines, parentheticals, scene headings,
/// and action mentions for a character. This evidence is fed to the LLM-based
/// `CharacterAnalyzer` to produce a `CharacterProfile`.
public struct CharacterEvidence: Codable, Sendable {
    /// The character's name (normalized to uppercase).
    public let characterName: String

    /// All dialogue lines spoken by this character.
    public var dialogueLines: [String]

    /// All parenthetical directions associated with this character's dialogue blocks.
    public var parentheticals: [String]

    /// Scene headings for scenes where this character appears (speaks).
    public var sceneHeadings: [String]

    /// Action lines that mention this character by name.
    public var actionMentions: [String]

    public init(
        characterName: String,
        dialogueLines: [String] = [],
        parentheticals: [String] = [],
        sceneHeadings: [String] = [],
        actionMentions: [String] = []
    ) {
        self.characterName = characterName
        self.dialogueLines = dialogueLines
        self.parentheticals = parentheticals
        self.sceneHeadings = sceneHeadings
        self.actionMentions = actionMentions
    }
}
```

---

### 2. CharacterEvidenceExtractor.swift

Walks an array of screenplay elements and collects per-character evidence. Pure synchronous logic with no external dependencies beyond SwiftCompartido's `GuionElementProtocol`. This is the first stage of the pipeline.

```swift
//
//  CharacterEvidenceExtractor.swift
//  SwiftVoxAlta
//
//  Extracts character evidence from screenplay elements for voice design analysis.
//

import Foundation
import SwiftCompartido

/// Extracts `CharacterEvidence` from a sequence of screenplay elements.
///
/// Walks the element array sequentially. When a `.character` element is found,
/// collects subsequent `.dialogue` and `.parenthetical` elements until the next
/// `.character` or non-dialogue element. Also tracks which scene headings and
/// action lines mention each character by name (case-insensitive).
public struct CharacterEvidenceExtractor: Sendable {

    /// Extract character evidence from an array of screenplay elements.
    ///
    /// - Parameter elements: Screenplay elements in document order. Accepts any type
    ///   conforming to `GuionElementProtocol` (e.g., `GuionElement`, `GuionElementModel`).
    /// - Returns: A dictionary keyed by character name (normalized to uppercase)
    ///   mapping to the collected `CharacterEvidence`.
    public static func extract(from elements: [any GuionElementProtocol]) -> [String: CharacterEvidence] {
        var evidenceByName: [String: CharacterEvidence] = [:]

        // Track the most recent scene heading for associating with characters
        var currentSceneHeading: String?

        // Track which characters have been associated with the current scene heading
        var charactersInCurrentScene: Set<String> = []

        // First pass: extract dialogue blocks and track scene headings
        var currentCharacterName: String?

        for element in elements {
            switch element.elementType {
            case .sceneHeading:
                currentSceneHeading = element.elementText
                charactersInCurrentScene = []
                currentCharacterName = nil

            case .character:
                let name = normalizeCharacterName(element.elementText)
                currentCharacterName = name

                // Initialize evidence if this is a new character
                if evidenceByName[name] == nil {
                    evidenceByName[name] = CharacterEvidence(characterName: name)
                }

                // Associate this character with the current scene heading
                if let heading = currentSceneHeading, !charactersInCurrentScene.contains(name) {
                    evidenceByName[name]?.sceneHeadings.append(heading)
                    charactersInCurrentScene.insert(name)
                }

            case .dialogue:
                if let name = currentCharacterName {
                    evidenceByName[name]?.dialogueLines.append(element.elementText)
                }

            case .parenthetical:
                if let name = currentCharacterName {
                    evidenceByName[name]?.parentheticals.append(element.elementText)
                }

            default:
                // Any non-dialogue element ends the current dialogue block
                if element.elementType != .dialogue && element.elementType != .parenthetical {
                    currentCharacterName = nil
                }
            }
        }

        // Second pass: scan action lines for character name mentions
        let characterNames = Array(evidenceByName.keys)
        for element in elements {
            if element.elementType == .action {
                let actionText = element.elementText.uppercased()
                for name in characterNames {
                    if actionText.contains(name) {
                        evidenceByName[name]?.actionMentions.append(element.elementText)
                    }
                }
            }
        }

        return evidenceByName
    }

    /// Normalize a character name by trimming whitespace and converting to uppercase.
    ///
    /// Also strips common Fountain extensions like "(V.O.)", "(O.S.)", "(O.C.)",
    /// "(CONT'D)", etc.
    private static func normalizeCharacterName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespaces)

        // Remove common Fountain character extensions in parentheses
        // e.g., "JOHN (V.O.)" -> "JOHN", "MARY (CONT'D)" -> "MARY"
        let extensionPattern = #"\s*\((?:V\.O\.|O\.S\.|O\.C\.|CONT'D|CONT\.)\)\s*$"#
        if let regex = try? NSRegularExpression(pattern: extensionPattern, options: .caseInsensitive) {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        }

        return name.uppercased().trimmingCharacters(in: .whitespaces)
    }
}
```

---

### 3. CharacterAnalyzer.swift

Takes `CharacterEvidence` and sends it to an on-device LLM (via SwiftBruja) to produce a structured `CharacterProfile`. The system prompt instructs the LLM to act as a voice casting director. Uses `Bruja.query(_:as:)` for structured JSON decoding directly into `CharacterProfile`.

```swift
//
//  CharacterAnalyzer.swift
//  SwiftVoxAlta
//
//  Analyzes character evidence from screenplays to produce voice profiles via LLM inference.
//

import Foundation
import SwiftBruja

/// Analyzes `CharacterEvidence` using an on-device LLM to produce a `CharacterProfile`
/// suitable for Qwen3-TTS VoiceDesign prompt generation.
///
/// `CharacterAnalyzer` calls SwiftBruja's structured output API to infer gender, age range,
/// voice traits, and a prose voice description from the character's dialogue lines,
/// parentheticals, scene headings, and action mentions.
public enum CharacterAnalyzer: Sendable {

    /// The system prompt instructing the LLM how to analyze character evidence for TTS voice design.
    static let systemPrompt: String = """
        You are a voice casting director analyzing a screenplay character for text-to-speech voice design.

        Given evidence about a character (their dialogue lines, parenthetical directions, \
        scene headings where they appear, and action descriptions mentioning them), \
        produce a JSON object describing the character's voice profile.

        The JSON must have exactly these fields:
        - "name": The character's name in UPPERCASE (string)
        - "gender": One of "male", "female", "nonBinary", or "unknown" (string)
        - "ageRange": A short description of approximate age (e.g., "30s", "elderly", "young adult", "teenager") (string)
        - "description": A prose description of the character's personality and vocal qualities, 1-3 sentences (string)
        - "voiceTraits": An array of 3-6 descriptive adjectives or short phrases for TTS voice design \
        (e.g., "gravelly", "warm", "clipped speech", "southern drawl") (array of strings)
        - "summary": A concise 1-2 sentence voice description combining gender, age, and key vocal traits, \
        suitable for direct use as a TTS voice design prompt (string)

        Base your analysis on the evidence provided. If gender or age cannot be determined, use "unknown" \
        for gender and "adult" for ageRange. Focus on vocal qualities that would help a TTS system \
        generate an appropriate voice.

        Respond ONLY with the JSON object. No additional text.
        """

    /// Formats the character evidence into a user prompt for the LLM.
    ///
    /// - Parameter evidence: The extracted character evidence from the screenplay.
    /// - Returns: A formatted string containing all evidence for LLM analysis.
    static func formatUserPrompt(from evidence: CharacterEvidence) -> String {
        var parts: [String] = []

        parts.append("Analyze the following screenplay character for voice design.")
        parts.append("")
        parts.append("CHARACTER NAME: \(evidence.characterName)")

        if !evidence.dialogueLines.isEmpty {
            parts.append("")
            parts.append("DIALOGUE LINES:")
            for (index, line) in evidence.dialogueLines.prefix(20).enumerated() {
                parts.append("  \(index + 1). \"\(line)\"")
            }
            if evidence.dialogueLines.count > 20 {
                parts.append("  ... and \(evidence.dialogueLines.count - 20) more lines")
            }
        }

        if !evidence.parentheticals.isEmpty {
            parts.append("")
            parts.append("PARENTHETICAL DIRECTIONS:")
            for parenthetical in evidence.parentheticals {
                parts.append("  - \(parenthetical)")
            }
        }

        if !evidence.sceneHeadings.isEmpty {
            parts.append("")
            parts.append("SCENES WHERE CHARACTER APPEARS:")
            for heading in evidence.sceneHeadings {
                parts.append("  - \(heading)")
            }
        }

        if !evidence.actionMentions.isEmpty {
            parts.append("")
            parts.append("ACTION DESCRIPTIONS MENTIONING CHARACTER:")
            for (index, mention) in evidence.actionMentions.prefix(10).enumerated() {
                parts.append("  \(index + 1). \"\(mention)\"")
            }
            if evidence.actionMentions.count > 10 {
                parts.append("  ... and \(evidence.actionMentions.count - 10) more mentions")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Analyzes character evidence to produce a voice profile using LLM inference.
    ///
    /// Sends the character's dialogue, parentheticals, scene headings, and action mentions
    /// to an on-device LLM via SwiftBruja, which returns a structured `CharacterProfile`
    /// suitable for TTS voice design.
    ///
    /// - Parameters:
    ///   - evidence: The `CharacterEvidence` extracted from the screenplay.
    ///   - model: The HuggingFace model ID to use for analysis. Defaults to `Bruja.defaultModel`.
    /// - Returns: A `CharacterProfile` containing the inferred voice characteristics.
    /// - Throws: `VoxAltaError.profileAnalysisFailed` if the LLM call or JSON decoding fails.
    public static func analyze(
        evidence: CharacterEvidence,
        model: String = Bruja.defaultModel
    ) async throws -> CharacterProfile {
        let userPrompt = formatUserPrompt(from: evidence)

        do {
            let profile: CharacterProfile = try await Bruja.query(
                userPrompt,
                as: CharacterProfile.self,
                model: model,
                temperature: 0.3,
                maxTokens: 1024,
                system: systemPrompt
            )
            return profile
        } catch {
            throw VoxAltaError.profileAnalysisFailed(
                "Failed to analyze character '\(evidence.characterName)': \(error.localizedDescription)"
            )
        }
    }
}
```

---

### 4. SampleSentenceGenerator.swift

Generates a character-appropriate sample sentence via LLM, so voice audition clips sound natural rather than using a generic "hello" phrase. Has two entry points: one taking a full `CharacterProfile`, another taking a freeform voice description string.

```swift
//
//  SampleSentenceGenerator.swift
//  SwiftVoxAlta
//
//  Generates character-appropriate sample sentences for voice audition via LLM inference.
//

import Foundation
import SwiftBruja

/// Generates unique, character-appropriate sample sentences for voice previews
/// using an on-device LLM via SwiftBruja.
///
/// Instead of using the same static sentence for every voice generation,
/// `SampleSentenceGenerator` produces a sentence that matches the character's
/// personality, age, and vocal style -- making audition samples sound natural.
public enum SampleSentenceGenerator: Sendable {

    /// System prompt instructing the LLM to produce a single sample sentence.
    static let systemPrompt: String = """
        You are a dialogue writer. Given a character voice description, write a single \
        natural-sounding sentence (15-30 words) that this character might say. \
        The sentence should showcase the character's vocal qualities -- tone, pace, \
        and personality -- so a listener can judge the voice.

        Rules:
        - Output ONLY the sentence, no quotes, no attribution, no explanation.
        - Do not start with "Hello" or "Hi" or any greeting.
        - Make it conversational and natural, not a tongue-twister.
        - Include a mix of vowel and consonant sounds for phonetic variety.
        """

    /// Generate a sample sentence appropriate for a character profile.
    ///
    /// - Parameters:
    ///   - profile: The character profile to generate a sentence for.
    ///   - model: The HuggingFace model ID. Defaults to `Bruja.defaultModel`.
    /// - Returns: A character-appropriate sentence string.
    /// - Throws: If the LLM call fails.
    public static func generate(
        for profile: CharacterProfile,
        model: String = Bruja.defaultModel
    ) async throws -> String {
        let userPrompt = """
            Character: \(profile.name)
            Gender: \(profile.gender.rawValue)
            Age: \(profile.ageRange)
            Voice: \(profile.summary)
            Traits: \(profile.voiceTraits.joined(separator: ", "))
            """

        let sentence = try await Bruja.query(
            userPrompt,
            model: model,
            temperature: 0.8,
            maxTokens: 64,
            system: systemPrompt
        )

        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate a sample sentence from a freeform voice description string.
    ///
    /// Used when there is no full `CharacterProfile` available (e.g., `--design` flag).
    ///
    /// - Parameters:
    ///   - description: A prose voice description (e.g., "warm, mature female voice in her 50s").
    ///   - name: The voice/character name.
    ///   - model: The HuggingFace model ID. Defaults to `Bruja.defaultModel`.
    /// - Returns: A voice-appropriate sentence string.
    /// - Throws: If the LLM call fails.
    public static func generate(
        fromDescription description: String,
        name: String,
        model: String = Bruja.defaultModel
    ) async throws -> String {
        let userPrompt = """
            Character: \(name)
            Voice description: \(description)
            """

        let sentence = try await Bruja.query(
            userPrompt,
            model: model,
            temperature: 0.8,
            maxTokens: 64,
            system: systemPrompt
        )

        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

---

### 5. VoiceDesigner.swift

Composes Qwen3-TTS VoiceDesign description strings from `CharacterProfile` data and generates candidate WAV audio. The `composeVoiceDescription` method is pure (no model needed); `generateCandidate` and `generateCandidates` require a loaded VoiceDesign model. Multiple candidates are generated concurrently via `TaskGroup` for A/B comparison.

Note: References `VoxAltaModelManager` and `AudioConversion` which are VoxAlta internals. In SwiftEchada, you will need equivalent model loading and audio conversion utilities.

```swift
//
//  VoiceDesigner.swift
//  SwiftVoxAlta
//
//  Composes voice descriptions from character profiles and generates voice candidates
//  using Qwen3-TTS VoiceDesign models.
//

import Foundation
@preconcurrency import MLXAudioTTS
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

/// Internal logger for VoiceDesigner performance metrics.
/// Writes to stderr to match the project-wide logging convention.
private enum VoiceDesignerLogger {
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[VoiceDesigner] \(message)\n".utf8))
    }
}

/// Voice design utilities for composing voice descriptions and generating candidate audio
/// from `CharacterProfile` data using Qwen3-TTS VoiceDesign models.
///
/// `VoiceDesigner` is an enum namespace with static methods. It does not hold state.
/// Voice description composition is pure (no model needed); candidate generation
/// requires a loaded VoiceDesign model via `VoxAltaModelManager`.
public enum VoiceDesigner: Sendable {

    /// A sample text used for voice candidate generation.
    /// This text is synthesized with the designed voice to produce an audible preview.
    static let sampleText = "Hello, this is a voice sample for testing purposes."

    /// A phoneme pangram covering all English phonemes for voice sample generation.
    /// Used to produce a representative audio sample when creating a new voice.
    public static let phonemePangram = "That quick beige fox jumped in the air over each thin dog. Look out, I shout, for he's foiled you again, creating chaos."

    // MARK: - Voice Description Composition

    /// Compose a Qwen3-TTS VoiceDesign description string from a character profile.
    ///
    /// The resulting string is suitable for use as the `voice` parameter when calling
    /// `Qwen3TTSModel.generate()` on a VoiceDesign model. The format is:
    ///
    ///     "A {gender} voice, {ageRange}. {summary}. Voice traits: {traits joined}."
    ///
    /// - Parameter profile: The character profile to compose a description from.
    /// - Returns: A voice description string for TTS VoiceDesign generation.
    public static func composeVoiceDescription(from profile: CharacterProfile) -> String {
        let genderWord: String
        switch profile.gender {
        case .male:
            genderWord = "male"
        case .female:
            genderWord = "female"
        case .nonBinary:
            genderWord = "non-binary"
        case .unknown:
            genderWord = "neutral"
        }

        var description = "A \(genderWord) voice, \(profile.ageRange). \(profile.summary)."

        if !profile.voiceTraits.isEmpty {
            let traitsJoined = profile.voiceTraits.joined(separator: ", ")
            description += " Voice traits: \(traitsJoined)."
        }

        return description
    }

    // MARK: - Candidate Generation

    /// Generate a single voice candidate from a character profile using a VoiceDesign model.
    ///
    /// Loads the VoiceDesign model (if not already loaded), composes a voice description
    /// from the profile, and generates a sample audio clip. The returned Data is in
    /// WAV format (24kHz, 16-bit PCM, mono).
    ///
    /// - Parameters:
    ///   - profile: The character profile to design a voice for.
    ///   - modelManager: The model manager used to load the VoiceDesign model.
    ///   - sampleSentence: A character-appropriate sentence to synthesize. If nil,
    ///     falls back to the static `sampleText`.
    /// - Returns: WAV audio Data of the generated voice candidate.
    /// - Throws: `VoxAltaError.voiceDesignFailed` if generation fails,
    ///           `VoxAltaError.modelNotAvailable` if the model cannot be loaded.
    public static func generateCandidate(
        profile: CharacterProfile,
        modelManager: VoxAltaModelManager,
        sampleSentence: String? = nil
    ) async throws -> Data {
        // Load VoiceDesign model
        let model = try await modelManager.loadModel(.voiceDesign1_7B)

        // Cast to Qwen3TTSModel for access to Qwen3-specific API
        guard let qwenModel = model as? Qwen3TTSModel else {
            throw VoxAltaError.voiceDesignFailed(
                "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
            )
        }

        // Compose voice description
        let voiceDescription = composeVoiceDescription(from: profile)

        // Generate audio via the SpeechGenerationModel protocol
        let generationParams = GenerateParameters(
            temperature: 0.7,
            topP: 0.9,
            repetitionPenalty: 1.1
        )

        let audioArray: MLXArray
        do {
            audioArray = try await qwenModel.generate(
                text: sampleSentence ?? sampleText,
                voice: voiceDescription,
                refAudio: nil,
                refText: nil,
                language: "en",
                generationParameters: generationParams
            )
        } catch {
            throw VoxAltaError.voiceDesignFailed(
                "Failed to generate voice candidate for '\(profile.name)': \(error.localizedDescription)"
            )
        }

        // Convert MLXArray to WAV Data
        do {
            return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
        } catch {
            throw VoxAltaError.audioExportFailed(
                "Failed to convert generated audio to WAV: \(error.localizedDescription)"
            )
        }
    }

    /// Generate multiple voice candidates from a character profile using parallel generation.
    ///
    /// Each candidate uses the same voice description but will produce a slightly
    /// different voice due to sampling stochasticity. The returned array contains
    /// WAV format Data for each candidate, ordered by candidate index.
    ///
    /// Candidates are generated concurrently using a `TaskGroup`. The VoiceDesign model
    /// is loaded once before spawning tasks, and all tasks share the same model instance.
    /// Performance metrics (total wall-clock time and per-candidate timing) are logged
    /// to stderr.
    ///
    /// - Parameters:
    ///   - profile: The character profile to design voices for.
    ///   - count: The number of candidates to generate. Defaults to 3.
    ///   - modelManager: The model manager used to load the VoiceDesign model.
    ///   - sampleSentence: A character-appropriate sentence to synthesize. If nil,
    ///     falls back to the static `sampleText`.
    /// - Returns: An array of WAV audio Data, one per candidate, in index order.
    /// - Throws: `VoxAltaError.voiceDesignFailed` if any generation fails,
    ///           `VoxAltaError.modelNotAvailable` if the model cannot be loaded.
    public static func generateCandidates(
        profile: CharacterProfile,
        count: Int = 3,
        modelManager: VoxAltaModelManager,
        sampleSentence: String? = nil
    ) async throws -> [Data] {
        let clock = ContinuousClock()
        let totalStart = clock.now

        // Pre-load the VoiceDesign model once (avoids redundant actor calls per task)
        let model = try await modelManager.loadModel(.voiceDesign1_7B)

        guard let qwenModel = model as? Qwen3TTSModel else {
            throw VoxAltaError.voiceDesignFailed(
                "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
            )
        }

        // Compose the voice description once (pure function, no model needed)
        let voiceDescription = composeVoiceDescription(from: profile)

        let generationParams = GenerateParameters(
            temperature: 0.7,
            topP: 0.9,
            repetitionPenalty: 1.1
        )

        VoiceDesignerLogger.log(
            "Generating \(count) candidate(s) for '\(profile.name)' in parallel..."
        )

        // Generate candidates concurrently using TaskGroup.
        // Each task returns (index, Data) to preserve ordering.
        let indexedCandidates: [(Int, Data)] = try await withThrowingTaskGroup(
            of: (Int, Data).self
        ) { group in
            for index in 0..<count {
                group.addTask {
                    let candidateStart = clock.now

                    let audioArray: MLXArray
                    do {
                        audioArray = try await qwenModel.generate(
                            text: sampleSentence ?? sampleText,
                            voice: voiceDescription,
                            refAudio: nil,
                            refText: nil,
                            language: "en",
                            generationParameters: generationParams
                        )
                    } catch {
                        throw VoxAltaError.voiceDesignFailed(
                            "Failed to generate voice candidate \(index) for '\(profile.name)': \(error.localizedDescription)"
                        )
                    }

                    let wavData: Data
                    do {
                        wavData = try AudioConversion.mlxArrayToWAVData(
                            audioArray, sampleRate: qwenModel.sampleRate
                        )
                    } catch {
                        throw VoxAltaError.audioExportFailed(
                            "Failed to convert candidate \(index) audio to WAV: \(error.localizedDescription)"
                        )
                    }

                    let candidateElapsed = clock.now - candidateStart
                    VoiceDesignerLogger.log(
                        "Candidate \(index) generated in \(candidateElapsed)"
                    )

                    return (index, wavData)
                }
            }

            // Collect all results, preserving order
            var results: [(Int, Data)] = []
            results.reserveCapacity(count)

            for try await result in group {
                results.append(result)
            }

            return results
        }

        // Sort by index to ensure deterministic output order
        let candidates = indexedCandidates
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        let totalElapsed = clock.now - totalStart
        VoiceDesignerLogger.log(
            "All \(count) candidate(s) generated in \(totalElapsed) (wall-clock)"
        )

        return candidates
    }
}
```

---

### 6. ParentheticalMapper.swift

Translates screenplay parentheticals into Qwen3-TTS instruct strings for runtime voice modulation. Contains a static lookup table for ~30 common vocal parentheticals and a set of known blocking/physical parentheticals that return `nil`. Falls back to LLM classification (via SwiftBruja) for unknown entries. This is used at synthesis time, not just at casting time, so it may need to live in a shared location or be duplicated.

```swift
//
//  ParentheticalMapper.swift
//  SwiftVoxAlta
//
//  Maps screenplay parentheticals to TTS instruct strings for Qwen3-TTS voice modulation.
//

import Foundation
import SwiftBruja

/// Maps screenplay parentheticals to TTS instruct strings.
///
/// Parentheticals like `(whispering)` or `(angrily)` provide vocal direction that
/// can be translated into Qwen3-TTS instruct parameters. `ParentheticalMapper` first
/// checks a static lookup table of common parentheticals, and falls back to LLM
/// classification for unknown entries.
///
/// Parentheticals that represent blocking/physical direction (e.g., `(beat)`, `(turning)`)
/// rather than vocal modulation return `nil`, indicating no TTS instruct modification.
public enum ParentheticalMapper: Sendable {

    // MARK: - Static Lookup Table

    /// Known vocal parenthetical mappings to TTS instruct strings.
    /// Keys are normalized (lowercase, no parentheses).
    private static let vocalMappings: [String: String] = [
        "whispering": "speak in a whisper",
        "shouting": "speak loudly and forcefully",
        "sarcastic": "speak with a sarcastic tone",
        "sarcastically": "speak with a sarcastic tone",
        "angrily": "speak angrily",
        "angry": "speak angrily",
        "softly": "speak softly and gently",
        "soft": "speak softly and gently",
        "laughing": "speak while laughing",
        "crying": "speak while crying, with emotion",
        "nervously": "speak nervously, with hesitation",
        "nervous": "speak nervously, with hesitation",
        "excited": "speak with excitement and energy",
        "excitedly": "speak with excitement and energy",
        "monotone": "speak in a flat, monotone voice",
        "singing": "speak in a sing-song manner",
        "to herself": "speak quietly, as if talking to oneself",
        "to himself": "speak quietly, as if talking to oneself",
        "to themselves": "speak quietly, as if talking to oneself",
        "under breath": "speak quietly, as if talking to oneself",
        "under his breath": "speak quietly, as if talking to oneself",
        "under her breath": "speak quietly, as if talking to oneself",
        "yelling": "speak loudly and forcefully",
        "screaming": "speak loudly and forcefully",
        "quietly": "speak softly and gently",
        "hushed": "speak in a whisper",
        "pleading": "speak with a pleading, desperate tone",
        "coldly": "speak in a cold, detached tone",
        "cheerfully": "speak with excitement and energy",
        "sadly": "speak with sadness and emotion",
        "fearfully": "speak nervously, with hesitation",
        "firmly": "speak firmly and with authority",
    ]

    /// Known blocking/physical parentheticals that should return `nil`.
    /// Keys are normalized (lowercase, no parentheses).
    private static let blockingParentheticals: Set<String> = [
        "beat",
        "pause",
        "a beat",
        "long pause",
        "turning",
        "turning away",
        "turning to",
        "walking away",
        "standing",
        "sitting",
        "sitting down",
        "standing up",
        "entering",
        "exiting",
        "crossing",
        "moving to",
        "picking up",
        "putting down",
        "looking at",
        "looking away",
        "pointing",
        "gesturing",
        "nodding",
        "shaking head",
        "into phone",
        "into the phone",
        "reading",
        "writing",
    ]

    // MARK: - Normalization

    /// Normalizes a parenthetical string by stripping outer parentheses,
    /// trimming whitespace, and converting to lowercase.
    ///
    /// - Parameter parenthetical: The raw parenthetical string (e.g., "(Whispering)").
    /// - Returns: The normalized key (e.g., "whispering").
    static func normalize(_ parenthetical: String) -> String {
        var text = parenthetical.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip outer parentheses
        if text.hasPrefix("(") && text.hasSuffix(")") {
            text = String(text.dropFirst().dropLast())
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.lowercased()
    }

    // MARK: - Static Mapping

    /// Maps a parenthetical to a TTS instruct string using the static lookup table.
    ///
    /// Returns `nil` for:
    /// - Blocking/physical direction parentheticals (e.g., "(beat)", "(turning)")
    /// - Unknown parentheticals not in the static table
    ///
    /// - Parameter parenthetical: The raw parenthetical string (e.g., "(whispering)").
    /// - Returns: A TTS instruct string, or `nil` if the parenthetical is non-vocal or unknown.
    public static func mapToInstruct(_ parenthetical: String) -> String? {
        let key = normalize(parenthetical)

        // Check vocal mappings first
        if let instruct = vocalMappings[key] {
            return instruct
        }

        // Check if it's a known blocking parenthetical (explicit nil)
        if blockingParentheticals.contains(key) {
            return nil
        }

        // Unknown -- return nil from the static version
        return nil
    }

    // MARK: - LLM Fallback

    /// The system prompt for LLM-based parenthetical classification.
    static let classificationSystemPrompt: String = """
        You are a screenplay analysis assistant. Given a parenthetical direction from a screenplay, \
        classify it as either "vocal" or "blocking".

        - "vocal" means it describes HOW the character speaks (tone, emotion, volume, manner of speech).
        - "blocking" means it describes a physical action, movement, or stage direction (not about voice).

        If it is "vocal", also provide a short TTS instruction describing how to speak the line.

        Respond ONLY with JSON in this exact format:
        {"classification": "vocal", "instruct": "speak with ..."}
        or
        {"classification": "blocking"}

        No additional text.
        """

    /// Internal type for decoding the LLM classification response.
    private struct ClassificationResult: Codable, Sendable {
        let classification: String
        let instruct: String?
    }

    /// Maps a parenthetical to a TTS instruct string, falling back to LLM classification
    /// for parentheticals not found in the static table.
    ///
    /// First checks the static table. If the parenthetical is unknown, queries the LLM
    /// to classify it as "vocal" or "blocking" and returns the appropriate instruct string.
    ///
    /// - Parameters:
    ///   - parenthetical: The raw parenthetical string (e.g., "(trembling)").
    ///   - model: The HuggingFace model ID to use for LLM classification.
    /// - Returns: A TTS instruct string, or `nil` if the parenthetical is non-vocal.
    /// - Throws: `VoxAltaError.profileAnalysisFailed` if the LLM call fails.
    public static func mapToInstruct(
        _ parenthetical: String,
        model: String
    ) async throws -> String? {
        let key = normalize(parenthetical)

        // Check static tables first
        if let instruct = vocalMappings[key] {
            return instruct
        }

        if blockingParentheticals.contains(key) {
            return nil
        }

        // LLM fallback for unknown parentheticals
        let userPrompt = "Classify this screenplay parenthetical: (\(key))"

        let result: ClassificationResult
        do {
            result = try await Bruja.query(
                userPrompt,
                as: ClassificationResult.self,
                model: model,
                temperature: 0.1,
                maxTokens: 128,
                system: classificationSystemPrompt
            )
        } catch {
            throw VoxAltaError.profileAnalysisFailed(
                "Failed to classify parenthetical '(\(key))': \(error.localizedDescription)"
            )
        }

        if result.classification == "vocal", let instruct = result.instruct {
            return instruct
        }

        return nil
    }
}
```

---

### 7. ReferenceAudioGenerator.swift

A macOS-only fallback that generates reference audio using the `say` command (Apple's built-in TTS). Produces WAV files at 24kHz/16-bit PCM to match Qwen3-TTS expectations. Used when VoiceDesign is unavailable or when quick reference audio is needed for voice cloning with the Base model. Lives in the `diga` CLI target, not the library.

```swift
import Foundation
import AVFoundation

/// Generates reference audio files for voice cloning using macOS `say` command.
///
/// Used as a fallback when VoiceDesign is unavailable or too slow. Generates
/// short audio samples using Apple's built-in TTS voices, which can then be
/// used with Qwen3-TTS Base model for voice cloning.
enum ReferenceAudioGenerator {

    /// Voice mappings from our voice names to macOS `say` voices
    private static let sayVoiceMap: [String: String] = [
        "alex": "Alex",           // Male, American
        "samantha": "Samantha",   // Female, American
        "daniel": "Daniel",       // Male, British
        "karen": "Karen",         // Female, Australian
    ]

    /// Sample text to use for reference audio generation.
    /// Should be short but include varied phonemes.
    private static let referenceText = "Hello, this is a test of my voice."

    /// Generate reference audio for a voice using macOS `say` command.
    ///
    /// - Parameters:
    ///   - voiceName: The voice name (e.g., "alex", "samantha")
    ///   - outputPath: File path where the audio should be saved (.wav or .aiff)
    /// - Throws: `ReferenceAudioError` if generation fails
    static func generate(voiceName: String, outputPath: URL) throws {
        guard let sayVoice = sayVoiceMap[voiceName] else {
            throw ReferenceAudioError.voiceNotFound(
                "No macOS voice mapping for '\(voiceName)'"
            )
        }

        // Create parent directory if needed
        let parentDir = outputPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        }

        // Use `say` to generate reference audio
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [
            "-v", sayVoice,
            "-o", outputPath.path,
            "--file-format=WAVE",  // WAV format for compatibility
            "--data-format=LEI16@24000",  // 16-bit PCM, 24kHz (matches Qwen3-TTS)
            referenceText
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ReferenceAudioError.generationFailed(
                "say command failed for voice '\(sayVoice)': \(errorMessage)"
            )
        }

        // Verify the file was created and has reasonable size
        guard FileManager.default.fileExists(atPath: outputPath.path) else {
            throw ReferenceAudioError.generationFailed(
                "Reference audio file not created at \(outputPath.path)"
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputPath.path)
        guard let fileSize = attributes[.size] as? Int, fileSize > 1000 else {
            throw ReferenceAudioError.generationFailed(
                "Reference audio file is too small (\(attributes[.size] ?? 0) bytes)"
            )
        }
    }

    /// Check if reference audio exists for a voice
    static func exists(voiceName: String, in directory: URL) -> Bool {
        let refPath = directory.appendingPathComponent("\(voiceName)-reference.wav")
        return FileManager.default.fileExists(atPath: refPath.path)
    }

    /// Get the path where reference audio should be stored
    static func referencePath(voiceName: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(voiceName)-reference.wav")
    }
}

// MARK: - Error Types

enum ReferenceAudioError: Error, LocalizedError {
    case voiceNotFound(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .voiceNotFound(let detail): return "Voice not found: \(detail)"
        case .generationFailed(let detail): return "Reference audio generation failed: \(detail)"
        }
    }
}
```

---

## Migration Notes

- **Error types**: The source code references `VoxAltaError` (e.g., `.profileAnalysisFailed`, `.voiceDesignFailed`, `.audioExportFailed`). SwiftEchada should define its own error enum or map these to a shared error type.
- **VoxAltaModelManager**: `VoiceDesigner` depends on `VoxAltaModelManager` for loading the Qwen3-TTS VoiceDesign model. In SwiftEchada, model loading should go through SwiftAcervo or whatever model management layer is available.
- **AudioConversion**: `VoiceDesigner` uses `AudioConversion.mlxArrayToWAVData()` to convert MLXArray output to WAV. This utility remains in VoxAlta and can be called as a dependency, or duplicated into SwiftEchada.
- **ParentheticalMapper dual use**: This mapper is used both at casting time (to understand a character's vocal range) and at synthesis time (to modulate individual lines). Consider whether it should live in a shared package (e.g., SwiftCompartido) rather than being duplicated.
- **ReferenceAudioGenerator** is macOS-only (uses `Process` and `/usr/bin/say`). It will not work on iOS. Guard with `#if os(macOS)` if SwiftEchada targets both platforms.
