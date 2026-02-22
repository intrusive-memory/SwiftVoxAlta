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
    /// Clone prompt binary data for the queried model, if present in the archive.
    public let clonePromptData: Data?
    /// Engine-generated sample audio WAV data, if present in the archive.
    public let sampleAudioData: Data?
    /// Reference audio data keyed by filename, extracted from the archive.
    public let referenceAudio: [String: Data]
    /// Creation timestamp from the manifest.
    public let createdAt: Date
    /// The full manifest for advanced use.
    public let manifest: VoxManifest
    /// Model identifiers this voice has embeddings for.
    public let supportedModels: [String]
}

/// Static methods for importing `.vox` voice identity files into VoxAlta.
public enum VoxImporter: Sendable {

    /// Import a `.vox` archive and extract its voice identity data.
    ///
    /// Uses the container-first `VoxFile(contentsOf:)` API. Clone prompt resolution
    /// is model-aware: the default query `"1.7b"` matches any 1.7B embedding, and
    /// falls back to the first available embedding if no match is found.
    ///
    /// - Parameters:
    ///   - url: Path to the `.vox` file.
    ///   - modelQuery: Model query string (e.g., `"0.6b"`, `"1.7b"`). Defaults to `"1.7b"`.
    /// - Returns: A `VoxImportResult` with extracted metadata and binary data.
    /// - Throws: `VoxAltaError.voxImportFailed` on failure.
    public static func importVox(from url: URL, modelQuery: String = "1.7b") throws -> VoxImportResult {
        do {
            let voxFile = try VoxFile(contentsOf: url)

            // Model-aware clone prompt lookup, with fallback to first available.
            let clonePromptData = voxFile.embeddingData(for: modelQuery)
                ?? voxFile.entries(under: "embeddings/").first?.data

            // Look for sample audio in embeddings.
            let sampleAudioData = voxFile["embeddings/qwen3-tts/sample-audio.wav"]?.data

            // Collect reference audio entries.
            var referenceAudio: [String: Data] = [:]
            for entry in voxFile.entries(under: "reference/") {
                let filename = String(entry.path.dropFirst("reference/".count))
                if !filename.isEmpty {
                    referenceAudio[filename] = entry.data
                }
            }

            return VoxImportResult(
                name: voxFile.manifest.voice.name,
                description: voxFile.manifest.voice.description,
                method: voxFile.manifest.provenance?.method,
                clonePromptData: clonePromptData,
                sampleAudioData: sampleAudioData,
                referenceAudio: referenceAudio,
                createdAt: voxFile.manifest.created,
                manifest: voxFile.manifest,
                supportedModels: voxFile.supportedModels
            )
        } catch let error as VoxAltaError {
            throw error
        } catch {
            throw VoxAltaError.voxImportFailed(error.localizedDescription)
        }
    }
}
