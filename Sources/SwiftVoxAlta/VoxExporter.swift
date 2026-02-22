import Foundation
@preconcurrency import VoxFormat

/// Static methods for exporting VoxAlta voices to the `.vox` portable container format.
public enum VoxExporter: Sendable {

    /// The default model identifier used for clone prompt embeddings.
    static let defaultCloneModel = "Qwen/Qwen3-TTS-12Hz-1.7B-Base-bf16"

    // MARK: - Model-Specific Path Helpers

    /// Returns a short slug for the given model repo (e.g. "0.6b" or "1.7b").
    public static func modelSizeSlug(for repo: Qwen3TTSModelRepo) -> String {
        switch repo {
        case .base0_6B, .customVoice0_6B:
            return "0.6b"
        case .base1_7B, .base1_7B_8bit, .base1_7B_4bit,
             .customVoice1_7B, .voiceDesign1_7B:
            return "1.7b"
        }
    }

    /// Returns the model-specific embedding archive path for a clone prompt.
    /// e.g. `"embeddings/qwen3-tts/0.6b/clone-prompt.bin"`
    public static func clonePromptPath(for repo: Qwen3TTSModelRepo) -> String {
        "embeddings/qwen3-tts/\(modelSizeSlug(for: repo))/clone-prompt.bin"
    }

    /// Returns the embedding archive path for sample audio.
    public static let sampleAudioPath = "embeddings/qwen3-tts/sample-audio.wav"

    // MARK: - Update Operations

    /// Update (or add) a model-specific clone prompt in an existing `.vox` archive.
    ///
    /// Opens the existing `.vox`, adds the clone prompt at the model-specific path,
    /// and writes the archive back. Other entries (including other models' clone prompts)
    /// are preserved.
    ///
    /// - Parameters:
    ///   - voxURL: Path to the existing `.vox` file.
    ///   - clonePromptData: The clone prompt binary data to embed.
    ///   - modelRepo: The model repo the clone prompt was generated with.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func updateClonePrompt(
        in voxURL: URL,
        clonePromptData: Data,
        modelRepo: Qwen3TTSModelRepo = .base1_7B
    ) throws {
        do {
            let vox = try VoxFile(contentsOf: voxURL)
            try vox.add(clonePromptData, at: clonePromptPath(for: modelRepo), metadata: [
                "model": modelRepo.rawValue,
                "engine": "qwen3-tts",
                "format": "bin",
                "description": "Clone prompt for voice cloning (\(modelSizeSlug(for: modelRepo)))",
            ])
            try vox.write(to: voxURL)
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxExportFailed("Failed to update clone prompt: \(error.localizedDescription)")
        }
    }

    /// Update (or add) the sample audio in an existing `.vox` archive.
    ///
    /// Opens the existing `.vox`, adds the sample audio WAV data, and writes back.
    /// Other entries are preserved.
    ///
    /// - Parameters:
    ///   - voxURL: Path to the existing `.vox` file.
    ///   - sampleAudioData: The WAV audio data to embed as a voice sample.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func updateSampleAudio(in voxURL: URL, sampleAudioData: Data) throws {
        do {
            let vox = try VoxFile(contentsOf: voxURL)
            try vox.add(sampleAudioData, at: sampleAudioPath, metadata: [
                "model": defaultCloneModel,
                "engine": "qwen3-tts",
                "format": "wav",
                "description": "Engine-generated voice sample",
            ])
            try vox.write(to: voxURL)
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxExportFailed("Failed to update sample audio: \(error.localizedDescription)")
        }
    }
}
