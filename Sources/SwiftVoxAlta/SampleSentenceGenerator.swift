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
/// personality, age, and vocal style — making audition samples sound natural.
public enum SampleSentenceGenerator: Sendable {

    /// System prompt instructing the LLM to produce a single sample sentence.
    static let systemPrompt: String = """
        You are a dialogue writer. Given a character voice description, write a single \
        natural-sounding sentence (15-30 words) that this character might say. \
        The sentence should showcase the character's vocal qualities — tone, pace, \
        and personality — so a listener can judge the voice.

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
