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
    /// - Returns: WAV audio Data of the generated voice candidate.
    /// - Throws: `VoxAltaError.voiceDesignFailed` if generation fails,
    ///           `VoxAltaError.modelNotAvailable` if the model cannot be loaded.
    public static func generateCandidate(
        profile: CharacterProfile,
        modelManager: VoxAltaModelManager
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
                text: sampleText,
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

    /// Generate multiple voice candidates from a character profile.
    ///
    /// Each candidate uses the same voice description but will produce a slightly
    /// different voice due to sampling stochasticity. The returned array contains
    /// WAV format Data for each candidate.
    ///
    /// - Parameters:
    ///   - profile: The character profile to design voices for.
    ///   - count: The number of candidates to generate. Defaults to 3.
    ///   - modelManager: The model manager used to load the VoiceDesign model.
    /// - Returns: An array of WAV audio Data, one per candidate.
    /// - Throws: `VoxAltaError.voiceDesignFailed` if any generation fails.
    public static func generateCandidates(
        profile: CharacterProfile,
        count: Int = 3,
        modelManager: VoxAltaModelManager
    ) async throws -> [Data] {
        var candidates: [Data] = []
        candidates.reserveCapacity(count)

        for _ in 0..<count {
            let candidate = try await generateCandidate(
                profile: profile,
                modelManager: modelManager
            )
            candidates.append(candidate)
        }

        return candidates
    }
}
