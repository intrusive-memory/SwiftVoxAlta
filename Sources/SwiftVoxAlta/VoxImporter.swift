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
    /// Clone prompt binary data, if present in the archive.
    public let clonePromptData: Data?
    /// Engine-generated sample audio WAV data, if present in the archive.
    public let sampleAudioData: Data?
    /// Reference audio data keyed by filename, extracted from the archive.
    public let referenceAudio: [String: Data]
    /// Creation timestamp from the manifest.
    public let createdAt: Date
    /// The full manifest for advanced use.
    public let manifest: VoxManifest
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

            // Extract clone prompt from embeddings if present.
            let clonePromptData = voxFile.embeddings[VoxExporter.clonePromptEmbeddingPath]

            // Extract sample audio from embeddings if present.
            let sampleAudioData = voxFile.embeddings[VoxExporter.sampleAudioEmbeddingPath]

            return VoxImportResult(
                name: voxFile.manifest.voice.name,
                description: voxFile.manifest.voice.description,
                method: voxFile.manifest.provenance?.method,
                clonePromptData: clonePromptData,
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
