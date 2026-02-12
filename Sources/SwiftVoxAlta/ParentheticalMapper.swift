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

        // Unknown — return nil from the static version
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
