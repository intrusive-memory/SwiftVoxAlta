import Foundation
@preconcurrency import VoxFormat

/// Result of importing a `.vox` voice identity file.
public struct VoxImportResult: Sendable {
    /// Voice display name.
    public let name: String
    /// Voice description.
    public let description: String
    /// Provenance method ("designed", "cloned", "preset").
    public let method: String?
    /// Clone prompt data keyed by model entry key (e.g. "qwen3-tts-0.6b", "qwen3-tts-1.7b").
    public let clonePromptsByModel: [String: Data]
    /// Engine-generated sample audio WAV data, if present in the archive.
    public let sampleAudioData: Data?
    /// Reference audio data keyed by filename, extracted from the archive.
    public let referenceAudio: [String: Data]
    /// Creation timestamp from the manifest.
    public let createdAt: Date
    /// The full manifest for advanced use.
    public let manifest: VoxManifest

    /// Returns the first available clone prompt data for backward compatibility.
    /// Prefers 1.7B over 0.6B if both exist.
    public var clonePromptData: Data? {
        clonePromptsByModel["qwen3-tts-1.7b"]
            ?? clonePromptsByModel["qwen3-tts-0.6b"]
            ?? clonePromptsByModel.values.first
    }

    /// Returns clone prompt data for a specific model size using substring matching.
    ///
    /// - Parameter modelQuery: A substring to match against entry keys (e.g. "0.6b", "1.7b").
    /// - Returns: The clone prompt data for the matched model, or nil.
    public func clonePromptData(for modelQuery: String) -> Data? {
        let query = modelQuery.lowercased()
        for (key, data) in clonePromptsByModel {
            if key.lowercased().contains(query) {
                return data
            }
        }
        return nil
    }
}

/// Static methods for importing `.vox` voice identity files into VoxAlta.
public enum VoxImporter: Sendable {

    /// Import a `.vox` archive and extract its voice identity data.
    ///
    /// - Parameter url: Path to the `.vox` file.
    /// - Returns: A `VoxImportResult` with extracted metadata and binary data.
    /// - Throws: `VoxAltaError.voxImportFailed` on failure.
    public static func importVox(from url: URL) throws -> VoxImportResult {
        do {
            let reader = VoxReader()
            let voxFile = try reader.read(from: url)

            // Build clone prompts dictionary from embedding entries.
            var clonePromptsByModel: [String: Data] = [:]

            if let entries = voxFile.manifest.embeddingEntries {
                for (key, entry) in entries {
                    // Match clone prompt entries (keys like "qwen3-tts-0.6b", "qwen3-tts-1.7b",
                    // or legacy "qwen3-tts-clone-prompt").
                    if entry.format == "bin",
                       entry.engine == "qwen3-tts",
                       let data = voxFile.embeddings[entry.file] {
                        clonePromptsByModel[key] = data
                    }
                }
            }

            // Legacy fallback: if no entries matched but the legacy path has data,
            // treat it as a 1.7B clone prompt.
            if clonePromptsByModel.isEmpty {
                if let legacyData = voxFile.embeddings[VoxExporter.legacyClonePromptEmbeddingPath] {
                    clonePromptsByModel["qwen3-tts-1.7b"] = legacyData
                }
            }

            // Extract sample audio from embeddings if present.
            let sampleAudioData = voxFile.embeddings[VoxExporter.sampleAudioEmbeddingPath]

            return VoxImportResult(
                name: voxFile.manifest.voice.name,
                description: voxFile.manifest.voice.description,
                method: voxFile.manifest.provenance?.method,
                clonePromptsByModel: clonePromptsByModel,
                sampleAudioData: sampleAudioData,
                referenceAudio: voxFile.referenceAudio,
                createdAt: voxFile.manifest.created,
                manifest: voxFile.manifest
            )
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxImportFailed(error.localizedDescription)
        }
    }
}
