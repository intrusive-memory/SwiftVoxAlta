//
//  VoiceLockManager.swift
//  SwiftVoxAlta
//
//  Creates and uses VoiceLocks for consistent voice identity across TTS generations.
//

import Foundation
@preconcurrency import MLXAudioTTS
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

/// Manages creation and use of `VoiceLock` instances for voice cloning.
///
/// `VoiceLockManager` is an enum namespace with static methods. It handles:
/// - Creating a `VoiceLock` from candidate audio (voice design output)
/// - Generating audio from a locked voice identity
///
/// Voice locking extracts a clone prompt (speaker embedding + reference codes) from
/// the selected voice candidate, serializes it, and stores it in a `VoiceLock`.
/// Subsequent audio generation uses the deserialized clone prompt for consistent
/// voice reproduction.
public enum VoiceLockManager: Sendable {

    /// A sample reference text describing the candidate audio content.
    /// Used when creating the voice clone prompt from the candidate audio.
    static let referenceSampleText = VoiceDesigner.sampleText

    // MARK: - Lock Creation

    /// Create a VoiceLock from candidate audio by extracting a voice clone prompt.
    ///
    /// Loads a Base model (which supports voice cloning), converts the candidate
    /// WAV audio to an MLXArray, and uses the model's speaker encoder to extract
    /// a reusable clone prompt. The clone prompt is serialized and stored in the
    /// returned `VoiceLock`.
    ///
    /// - Parameters:
    ///   - characterName: The character name to associate with this voice lock.
    ///   - candidateAudio: WAV format Data of the selected voice candidate
    ///     (output from `VoiceDesigner.generateCandidate`).
    ///   - designInstruction: The voice description text used to generate the candidate.
    ///   - modelManager: The model manager used to load the Base model.
    ///   - modelRepo: The Base model variant to use for cloning. Defaults to `.base1_7B`.
    /// - Returns: A `VoiceLock` containing the serialized clone prompt.
    /// - Throws: `VoxAltaError.cloningFailed` if clone prompt extraction fails,
    ///           `VoxAltaError.modelNotAvailable` if the Base model cannot be loaded.
    public static func createLock(
        characterName: String,
        candidateAudio: Data,
        designInstruction: String,
        modelManager: VoxAltaModelManager,
        modelRepo: Qwen3TTSModelRepo = .base1_7B
    ) async throws -> VoiceLock {
        // Load Base model (supports voice cloning)
        let model = try await modelManager.loadModel(modelRepo)

        // Cast to Qwen3TTSModel for clone prompt API
        guard let qwenModel = model as? Qwen3TTSModel else {
            throw VoxAltaError.cloningFailed(
                "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
            )
        }

        // Convert WAV Data to MLXArray
        let refAudio: MLXArray
        do {
            refAudio = try AudioConversion.wavDataToMLXArray(candidateAudio)
        } catch {
            throw VoxAltaError.cloningFailed(
                "Failed to parse candidate WAV audio: \(error.localizedDescription)"
            )
        }

        // Create voice clone prompt
        let clonePrompt: VoiceClonePrompt
        do {
            clonePrompt = try qwenModel.createVoiceClonePrompt(
                refAudio: refAudio,
                refText: referenceSampleText,
                language: "en"
            )
        } catch {
            throw VoxAltaError.cloningFailed(
                "Failed to create voice clone prompt for '\(characterName)': \(error.localizedDescription)"
            )
        }

        // Serialize clone prompt to Data
        let clonePromptData: Data
        do {
            clonePromptData = try clonePrompt.serialize()
        } catch {
            throw VoxAltaError.cloningFailed(
                "Failed to serialize voice clone prompt: \(error.localizedDescription)"
            )
        }

        return VoiceLock(
            characterName: characterName,
            clonePromptData: clonePromptData,
            designInstruction: designInstruction,
            lockedAt: Date()
        )
    }

    // MARK: - Audio Generation from Lock

    /// Generate speech audio using a locked voice identity.
    ///
    /// Deserializes the clone prompt from the voice lock and uses it to generate
    /// audio with a Base model. The resulting audio reproduces the locked voice
    /// identity consistently across calls.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceLock: The voice lock containing the serialized clone prompt.
    ///   - language: The language code for generation. Defaults to "en".
    ///   - modelManager: The model manager used to load the Base model.
    ///   - modelRepo: The Base model variant to use for generation. Defaults to `.base1_7B`.
    /// - Returns: WAV format Data of the generated speech audio (24kHz, 16-bit PCM, mono).
    /// - Throws: `VoxAltaError.cloningFailed` if generation fails,
    ///           `VoxAltaError.modelNotAvailable` if the Base model cannot be loaded.
    public static func generateAudio(
        text: String,
        voiceLock: VoiceLock,
        language: String = "en",
        modelManager: VoxAltaModelManager,
        modelRepo: Qwen3TTSModelRepo = .base1_7B
    ) async throws -> Data {
        // Load Base model
        let model = try await modelManager.loadModel(modelRepo)

        // Cast to Qwen3TTSModel
        guard let qwenModel = model as? Qwen3TTSModel else {
            throw VoxAltaError.cloningFailed(
                "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
            )
        }

        // Deserialize clone prompt
        let clonePrompt: VoiceClonePrompt
        do {
            clonePrompt = try VoiceClonePrompt.deserialize(from: voiceLock.clonePromptData)
        } catch {
            throw VoxAltaError.cloningFailed(
                "Failed to deserialize voice clone prompt for '\(voiceLock.characterName)': \(error.localizedDescription)"
            )
        }

        // Generate audio with clone prompt
        let audioArray: MLXArray
        do {
            audioArray = try qwenModel.generateWithClonePrompt(
                text: text,
                clonePrompt: clonePrompt,
                language: language
            )
        } catch {
            throw VoxAltaError.cloningFailed(
                "Failed to generate audio for '\(voiceLock.characterName)': \(error.localizedDescription)"
            )
        }

        // Convert to WAV Data
        do {
            return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
        } catch {
            throw VoxAltaError.audioExportFailed(
                "Failed to convert generated audio to WAV: \(error.localizedDescription)"
            )
        }
    }
}
