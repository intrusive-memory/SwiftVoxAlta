import Foundation
@preconcurrency import VoxFormat

/// Result of importing a `.vox` voice identity file.
public struct VoxImportResult: Sendable {
  /// Voice display name.
  public let name: String
  /// Voice description.
  public let description: String
  /// Provenance method ("designed", "synthesized", "cloned", "preset", "hybrid").
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
  /// BCP 47 language tags carried by this `.vox` for the queried model (from the sample-audio
  /// entries, via vox-format's `sampleAudioLanguages(for:)` discovery helper). Empty when the
  /// archive has only the default language-less entry. Lets a downstream consumer (e.g.
  /// Produciesta) discover which languages it can select. Fallback resolution itself is owned by
  /// vox-format's matchers — this list is for discovery only, not for re-deriving fallback here.
  public let availableLanguages: [String]
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
  ///   - modelQuery: Model query string (e.g., `"0.6b"`, `"1.7b"`). Defaults to `.base1_7B.slug`.
  /// - Returns: A `VoxImportResult` with extracted metadata and binary data.
  /// - Throws: `VoxAltaError.voxImportFailed` on failure.
  public static func importVox(from url: URL, modelQuery: String = Qwen3TTSModelRepo.base1_7B.slug)
    throws -> VoxImportResult
  {
    try importVox(from: url, modelQuery: modelQuery, language: nil)
  }

  /// Import a `.vox` archive, selecting embeddings for a specific language.
  ///
  /// When `language == nil` this is identical to the language-less import (the default and
  /// legacy behavior). When non-nil, clone-prompt and sample-audio selection is delegated to
  /// vox-format's language-aware matchers, which apply the locked fallback
  /// (exact → base-language, e.g. `fr-FR` → `fr` → default → nil). SwiftVoxAlta does NOT
  /// re-implement that fallback.
  ///
  /// - Parameters:
  ///   - url: Path to the `.vox` file.
  ///   - modelQuery: Model query string (e.g., `"0.6b"`, `"1.7b"`). Defaults to `.base1_7B.slug`.
  ///   - language: Optional BCP 47 language tag (e.g. `"es"`, `"fr-FR"`) to select. `nil` →
  ///     language-less selection (unchanged behavior).
  /// - Returns: A `VoxImportResult` with extracted metadata and binary data.
  /// - Throws: `VoxAltaError.voxImportFailed` on failure.
  public static func importVox(
    from url: URL,
    modelQuery: String = Qwen3TTSModelRepo.base1_7B.slug,
    language: String?
  ) throws -> VoxImportResult {
    do {
      let voxFile = try VoxFile(contentsOf: url)

      // Model-aware lookup. When a language is requested, delegate selection (and the locked
      // exact→base-language→default→nil fallback) to vox-format's language-aware matchers.
      let clonePromptData: Data?
      let sampleAudioData: Data?
      if let language {
        clonePromptData = voxFile.clonePromptData(for: modelQuery, language: language)
        sampleAudioData = voxFile.sampleAudioData(for: modelQuery, language: language)
      } else {
        clonePromptData = voxFile.clonePromptData(for: modelQuery)
        sampleAudioData = voxFile.sampleAudioData(for: modelQuery)
      }

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
        supportedModels: voxFile.supportedModels,
        availableLanguages: voxFile.sampleAudioLanguages(for: modelQuery)
      )
    } catch let error as VoxAltaError {
      throw error
    } catch {
      throw VoxAltaError.voxImportFailed(error.localizedDescription)
    }
  }
}
