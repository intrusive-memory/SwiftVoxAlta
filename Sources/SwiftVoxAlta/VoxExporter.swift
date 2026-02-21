import Foundation
@preconcurrency import VoxFormat

/// Static methods for exporting VoxAlta voices to the `.vox` portable container format.
public enum VoxExporter: Sendable {

    /// Legacy embeddings path for Qwen3-TTS clone prompts (pre-multi-model).
    /// Used as a fallback when reading old `.vox` files.
    static let legacyClonePromptEmbeddingPath = "qwen3-tts/clone-prompt.bin"

    /// The embeddings path within a `.vox` archive for engine-generated sample audio.
    public static let sampleAudioEmbeddingPath = "qwen3-tts/sample-audio.wav"

    /// The default model identifier used for clone prompt embeddings (legacy).
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

    /// Returns the model-specific embedding file path for a clone prompt.
    /// e.g. `"qwen3-tts/0.6b/clone-prompt.bin"`
    public static func clonePromptEmbeddingPath(for repo: Qwen3TTSModelRepo) -> String {
        "qwen3-tts/\(modelSizeSlug(for: repo))/clone-prompt.bin"
    }

    /// Returns the model-specific embedding entry key for a clone prompt.
    /// e.g. `"qwen3-tts-0.6b"`
    public static func clonePromptEntryKey(for repo: Qwen3TTSModelRepo) -> String {
        "qwen3-tts-\(modelSizeSlug(for: repo))"
    }

    // MARK: - Embedding Entry Helpers

    /// Build embedding entries for the given state, merging with any existing entries.
    static func buildEmbeddingEntries(
        clonePromptModelRepo: Qwen3TTSModelRepo? = nil,
        hasSampleAudio: Bool,
        existingEntries: [String: VoxManifest.EmbeddingEntry]? = nil
    ) -> [String: VoxManifest.EmbeddingEntry]? {
        var entries = existingEntries ?? [:]

        if let repo = clonePromptModelRepo {
            let key = clonePromptEntryKey(for: repo)
            entries[key] = VoxManifest.EmbeddingEntry(
                model: repo.rawValue,
                engine: "qwen3-tts",
                file: clonePromptEmbeddingPath(for: repo),
                format: "bin",
                description: "Clone prompt for voice cloning (\(modelSizeSlug(for: repo)))"
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
    ///   - clonePromptModelRepo: The model repo the clone prompt was generated with.
    ///     Defaults to `.base1_7B` for backward compatibility.
    ///   - referenceAudioURLs: URLs to reference audio files to include.
    ///   - to: Destination URL for the `.vox` file.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func export(
        manifest: VoxManifest,
        clonePromptData: Data? = nil,
        clonePromptModelRepo: Qwen3TTSModelRepo = .base1_7B,
        referenceAudioURLs: [URL] = [],
        to destination: URL
    ) throws {
        do {
            // Build embeddings dictionary.
            var embeddings: [String: Data] = [:]
            if let promptData = clonePromptData {
                embeddings[clonePromptEmbeddingPath(for: clonePromptModelRepo)] = promptData
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
                clonePromptModelRepo: clonePromptData != nil ? clonePromptModelRepo : nil,
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

    /// Update (or add) a model-specific clone prompt in an existing `.vox` archive.
    ///
    /// Reads the existing `.vox`, merges the new clone prompt with any existing
    /// embeddings (preserving other models' clone prompts and sample audio),
    /// then re-writes the archive.
    ///
    /// - Parameters:
    ///   - voxURL: Path to the existing `.vox` file.
    ///   - clonePromptData: The clone prompt binary data to embed.
    ///   - modelRepo: The model repo the clone prompt was generated with.
    ///     Defaults to `.base1_7B` for backward compatibility.
    /// - Throws: `VoxAltaError.voxExportFailed` on failure.
    public static func updateClonePrompt(
        in voxURL: URL,
        clonePromptData: Data,
        modelRepo: Qwen3TTSModelRepo = .base1_7B
    ) throws {
        do {
            let reader = VoxReader()
            let existing = try reader.read(from: voxURL)

            // Merge new clone prompt into existing embeddings.
            var embeddings = existing.embeddings
            embeddings[clonePromptEmbeddingPath(for: modelRepo)] = clonePromptData

            // Rebuild embedding entries, merging with existing ones.
            var manifest = existing.manifest
            manifest.embeddingEntries = buildEmbeddingEntries(
                clonePromptModelRepo: modelRepo,
                hasSampleAudio: embeddings[sampleAudioEmbeddingPath] != nil,
                existingEntries: existing.manifest.embeddingEntries
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
    /// Reads the existing `.vox`, merges the sample audio with existing embeddings
    /// (preserving clone prompt entries), then re-writes the archive.
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

            // Rebuild sample audio entry, merging with all existing entries.
            var manifest = existing.manifest
            var entries = existing.manifest.embeddingEntries ?? [:]
            entries["qwen3-tts-sample-audio"] = VoxManifest.EmbeddingEntry(
                model: defaultCloneModel,
                engine: "qwen3-tts",
                file: sampleAudioEmbeddingPath,
                format: "wav",
                description: "Engine-generated voice sample"
            )
            manifest.embeddingEntries = entries

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
