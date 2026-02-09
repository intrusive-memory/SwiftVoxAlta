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
