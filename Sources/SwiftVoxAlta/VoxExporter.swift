import Foundation
@preconcurrency import VoxFormat

/// Static methods for exporting VoxAlta voices to the `.vox` portable container format.
public enum VoxExporter: Sendable {

    /// The embeddings path within a `.vox` archive for Qwen3-TTS clone prompts.
    static let clonePromptEmbeddingPath = "qwen3-tts/clone-prompt.bin"

    /// The embeddings path within a `.vox` archive for engine-generated sample audio.
    public static let sampleAudioEmbeddingPath = "qwen3-tts/sample-audio.wav"

    /// The default model identifier used for clone prompt embeddings.
    static let defaultCloneModel = "Qwen/Qwen3-TTS-12Hz-1.7B-Base-bf16"

    // MARK: - Embedding Entry Helpers

    /// Build embedding entries for the given embeddings dictionary.
    static func buildEmbeddingEntries(
        hasClonePrompt: Bool,
        hasSampleAudio: Bool
    ) -> [String: VoxManifest.EmbeddingEntry]? {
        var entries: [String: VoxManifest.EmbeddingEntry] = [:]

        if hasClonePrompt {
            entries["qwen3-tts-clone-prompt"] = VoxManifest.EmbeddingEntry(
                model: defaultCloneModel,
                engine: "qwen3-tts",
                file: clonePromptEmbeddingPath,
                format: "bin",
                description: "Clone prompt for voice cloning"
            )
        }

        if hasSampleAudio {
            entries["qwen3-tts-sample-audio"] = VoxManifest.EmbeddingEntry(
                model: defaultCloneModel,
                engine: "qwen3-tts",
                file: sampleAudioEmbeddingPath,
                format: "wav",
                description: "Engine-generated voice sample"
            )
        }

        return entries.isEmpty ? nil : entries
    }

    // MARK: - Manifest Building

    /// Build a `VoxManifest` from a `VoiceLock`.
    ///
    /// - Parameters:
    ///   - voiceLock: The locked voice identity.
    ///   - voiceType: The provenance method (e.g. "designed", "cloned").
    ///   - language: BCP 47 language code (e.g. "en-US").
    /// - Returns: A populated `VoxManifest`.
    public static func buildManifest(
        from voiceLock: VoiceLock,
        voiceType: String,
        language: String = "en-US"
    ) -> VoxManifest {
        VoxManifest(
            voxVersion: VoxFormat.currentVersion,
            id: UUID().uuidString.lowercased(),
            created: voiceLock.lockedAt,
            voice: VoxManifest.Voice(
                name: voiceLock.characterName,
                description: voiceLock.designInstruction.count >= 10
                    ? voiceLock.designInstruction
                    : "Voice identity for \(voiceLock.characterName).",
                language: language
            ),
            provenance: VoxManifest.Provenance(
                method: voiceType,
                engine: "qwen3-tts"
            )
        )
    }

    /// Build a `VoxManifest` from explicit metadata (for creation-time export before a `VoiceLock` exists).
    ///
    /// - Parameters:
    ///   - name: Voice display name.
    ///   - description: Voice description (min 10 chars for validation).
    ///   - voiceType: Provenance method ("designed", "cloned", "preset").
    ///   - createdAt: Creation timestamp.
    ///   - language: BCP 47 language code.
    ///   - referenceAudioPaths: Paths to reference audio files for cloned voices.
    /// - Returns: A populated `VoxManifest`.
    public static func buildManifest(
        name: String,
        description: String?,
        voiceType: String,
        createdAt: Date = Date(),
        language: String = "en-US",
        referenceAudioPaths: [String] = []
    ) -> VoxManifest {
        let voiceDescription = {
            if let desc = description, desc.count >= 10 {
                return desc
            }
            return "Voice identity for \(name)."
        }()

        let referenceAudio: [VoxManifest.ReferenceAudio]? = referenceAudioPaths.isEmpty
            ? nil
            : referenceAudioPaths.map { path in
                let filename = URL(fileURLWithPath: path).lastPathComponent
                return VoxManifest.ReferenceAudio(
                    file: "reference/\(filename)",
                    transcript: ""
                )
            }

        return VoxManifest(
            voxVersion: VoxFormat.currentVersion,
            id: UUID().uuidString.lowercased(),
            created: createdAt,
            voice: VoxManifest.Voice(
                name: name,
                description: voiceDescription,
                language: language
            ),
            referenceAudio: referenceAudio,
            provenance: VoxManifest.Provenance(
                method: voiceType,
                engine: "qwen3-tts"
            )
        )
    }

    // MARK: - Export

    /// Export a voice as a `.vox` archive.
    ///
    /// - Parameters:
    ///   - manifest: The voice manifest.
    ///   - clonePromptData: Optional clone prompt binary data.
    ///   - referenceAudioURLs: URLs to reference audio files to include.
    ///   - to: Destination URL for the `.vox` file.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func export(
        manifest: VoxManifest,
        clonePromptData: Data? = nil,
        referenceAudioURLs: [URL] = [],
        to destination: URL
    ) throws {
        do {
            // Build embeddings dictionary.
            var embeddings: [String: Data] = [:]
            if let promptData = clonePromptData {
                embeddings[clonePromptEmbeddingPath] = promptData
            }

            // Read reference audio files into memory.
            var referenceAudio: [String: Data] = [:]
            for refURL in referenceAudioURLs {
                let data = try Data(contentsOf: refURL)
                referenceAudio[refURL.lastPathComponent] = data
            }

            // Populate embedding entries metadata.
            var exportManifest = manifest
            exportManifest.embeddingEntries = buildEmbeddingEntries(
                hasClonePrompt: clonePromptData != nil,
                hasSampleAudio: false
            )

            let voxFile = VoxFile(
                manifest: exportManifest,
                referenceAudio: referenceAudio,
                embeddings: embeddings
            )

            let writer = VoxWriter()
            try writer.write(voxFile, to: destination)
        } catch {
            throw VoxAltaError.voxExportFailed(error.localizedDescription)
        }
    }

    /// Update (or add) the clone prompt in an existing `.vox` archive.
    ///
    /// Reads the existing `.vox`, extracts its manifest and reference audio,
    /// then re-writes it with the clone prompt embedded.
    ///
    /// - Parameters:
    ///   - voxURL: Path to the existing `.vox` file.
    ///   - clonePromptData: The clone prompt binary data to embed.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func updateClonePrompt(in voxURL: URL, clonePromptData: Data) throws {
        do {
            let reader = VoxReader()
            let existing = try reader.read(from: voxURL)

            // Merge new clone prompt into existing embeddings.
            var embeddings = existing.embeddings
            embeddings[clonePromptEmbeddingPath] = clonePromptData

            // Rebuild embedding entries from the current state.
            var manifest = existing.manifest
            manifest.embeddingEntries = buildEmbeddingEntries(
                hasClonePrompt: true,
                hasSampleAudio: embeddings[sampleAudioEmbeddingPath] != nil
            )

            let updated = VoxFile(
                manifest: manifest,
                referenceAudio: existing.referenceAudio,
                embeddings: embeddings
            )

            let writer = VoxWriter()
            try writer.write(updated, to: voxURL)
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxExportFailed("Failed to update clone prompt: \(error.localizedDescription)")
        }
    }

    /// Update (or add) the sample audio in an existing `.vox` archive.
    ///
    /// Reads the existing `.vox`, extracts its manifest, reference audio, and embeddings,
    /// then re-writes it with the sample audio WAV data embedded.
    ///
    /// - Parameters:
    ///   - voxURL: Path to the existing `.vox` file.
    ///   - sampleAudioData: The WAV audio data to embed as a voice sample.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func updateSampleAudio(in voxURL: URL, sampleAudioData: Data) throws {
        do {
            let reader = VoxReader()
            let existing = try reader.read(from: voxURL)

            var embeddings = existing.embeddings
            embeddings[sampleAudioEmbeddingPath] = sampleAudioData

            // Rebuild embedding entries from the current state.
            var manifest = existing.manifest
            manifest.embeddingEntries = buildEmbeddingEntries(
                hasClonePrompt: embeddings[clonePromptEmbeddingPath] != nil,
                hasSampleAudio: true
            )

            let updated = VoxFile(
                manifest: manifest,
                referenceAudio: existing.referenceAudio,
                embeddings: embeddings
            )

            let writer = VoxWriter()
            try writer.write(updated, to: voxURL)
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxExportFailed("Failed to update sample audio: \(error.localizedDescription)")
        }
    }
}
