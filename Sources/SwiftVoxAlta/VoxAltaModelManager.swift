//
//  VoxAltaModelManager.swift
//  SwiftVoxAlta
//
//  Actor managing Qwen3-TTS model lifecycle via mlx-audio-swift.
//  Handles model loading, caching, unloading, and memory validation.
//

import Foundation
import MLXAudioTTS
import SwiftAcervo
import Tuberia

// MARK: - Supported Model Repos

/// Known Qwen3-TTS model repository identifiers on HuggingFace.
public enum Qwen3TTSModelRepo: String, CaseIterable, Sendable {
  /// VoiceDesign model (1.7B parameters, bf16 precision).
  /// Generates novel voices from text descriptions.
  case voiceDesign1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

  /// Base model (1.7B parameters, bf16 precision).
  /// Supports voice cloning from reference audio.
  case base1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

  /// Base model (0.6B parameters, bf16 precision).
  /// Lighter-weight voice cloning, suitable for draft rendering.
  case base0_6B = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"

  /// CustomVoice model (1.7B parameters, bf16 precision).
  /// Includes 9 preset speakers (no clone prompt needed).
  case customVoice1_7B = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"

  /// CustomVoice model (0.6B parameters, bf16 precision).
  /// Lighter-weight with 9 preset speakers.
  case customVoice0_6B = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"

  /// Base model (1.7B parameters, 8-bit quantized).
  /// Reduced memory footprint (~1.7GB) with minor quality loss.
  case base1_7B_8bit = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"

  /// Base model (1.7B parameters, 4-bit quantized).
  /// Smallest memory footprint (~850MB) but significant quality degradation.
  /// NOT recommended for production use.
  case base1_7B_4bit = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit"

  /// Short model-size slug used as a user-facing identifier and .vox query key.
  ///
  /// Examples: `"0.6b"`, `"1.7b"`.  All variants of the same parameter count
  /// share the same slug, so both `base1_7B` and `base1_7B_8bit` return `"1.7b"`.
  public var slug: String {
    switch self {
    case .base0_6B, .customVoice0_6B:
      return "0.6b"
    case .base1_7B, .base1_7B_8bit, .base1_7B_4bit,
      .customVoice1_7B, .voiceDesign1_7B:
      return "1.7b"
    }
  }

  /// The two supported model size slugs for CLI option validation.
  public static let supportedSlugs: Set<String> = ["0.6b", "1.7b"]

  /// Resolves a slug string to the default Base model repo for that size.
  ///
  /// - Parameter slug: A model size slug (e.g., `"0.6b"`, `"1.7b"`).
  /// - Returns: The corresponding Base model repo, or `nil` if unrecognized.
  public init?(slug: String) {
    switch slug.lowercased() {
    case "0.6b": self = .base0_6B
    case "1.7b": self = .base1_7B
    default: return nil
    }
  }

  /// Human-readable display name for the model variant.
  public var displayName: String {
    switch self {
    case .voiceDesign1_7B: return "VoiceDesign 1.7B (bf16)"
    case .base1_7B: return "Base 1.7B (bf16)"
    case .base0_6B: return "Base 0.6B (bf16)"
    case .customVoice1_7B: return "CustomVoice 1.7B (bf16)"
    case .customVoice0_6B: return "CustomVoice 0.6B (bf16)"
    case .base1_7B_8bit: return "Base 1.7B (8-bit)"
    case .base1_7B_4bit: return "Base 1.7B (4-bit)"
    }
  }
}

// MARK: - Model Size Constants

/// Memory-related constants for Qwen3-TTS model loading.
///
/// Model size estimates are now declared in `ComponentDescriptor.minimumMemoryBytes`
/// for each registered variant. This enum retains only the headroom multiplier
/// that is VoxAlta-specific (not model metadata).
public enum Qwen3TTSModelSize {
  /// The memory headroom multiplier applied to estimated model sizes.
  /// Models need additional memory for KV caches, intermediate activations,
  /// and the speech tokenizer during generation.
  public static let headroomMultiplier: Double = 1.5
}

// MARK: - Acervo Component Registration

extension Qwen3TTSModelRepo {
  /// The Acervo component ID for this model variant.
  ///
  /// Used to look up, download, and check availability of this model
  /// via the SwiftAcervo Component Registry.
  public var componentId: String {
    switch self {
    case .base1_7B: return "qwen3-tts-base-1.7b"
    case .base0_6B: return "qwen3-tts-base-0.6b"
    case .customVoice1_7B: return "qwen3-tts-custom-1.7b"
    case .customVoice0_6B: return "qwen3-tts-custom-0.6b"
    case .voiceDesign1_7B: return "qwen3-tts-voicedesign-1.7b"
    case .base1_7B_8bit: return "qwen3-tts-base-1.7b-8bit"
    case .base1_7B_4bit: return "qwen3-tts-base-1.7b-4bit"
    }
  }
}

/// Required files for any Qwen3-TTS model variant.
///
/// These files are declared in each `ComponentDescriptor` so that
/// `Acervo.ensureComponentReady()` knows exactly what to download.
/// Includes all core model config, tokenizer files (for tokenizer.json generation),
/// model weights (including index for sharded models), and speech tokenizer components.
private let qwen3TTSRequiredFiles: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "generation_config.json"),
  ComponentFile(relativePath: "preprocessor_config.json"),
  ComponentFile(relativePath: "tokenizer_config.json"),
  ComponentFile(relativePath: "vocab.json"),
  ComponentFile(relativePath: "merges.txt"),
  ComponentFile(relativePath: "model.safetensors"),
  ComponentFile(relativePath: "model.safetensors.index.json"),
  ComponentFile(relativePath: "speech_tokenizer/config.json"),
  ComponentFile(relativePath: "speech_tokenizer/configuration.json"),
  ComponentFile(relativePath: "speech_tokenizer/model.safetensors"),
  ComponentFile(relativePath: "speech_tokenizer/preprocessor_config.json"),
]

/// All 7 Qwen3-TTS component descriptors (6 active + 1 deprecated).
///
/// Registered at module initialization so the Acervo Component Registry
/// is populated before any model loading or download is attempted.
private let qwen3TTSComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 3_400_000_000,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base0_6B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 0.6B (bf16)",
    repoId: Qwen3TTSModelRepo.base0_6B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 1_200_000_000,
    minimumMemoryBytes: 1_200_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.customVoice1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS CustomVoice 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.customVoice1_7B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 3_400_000_000,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.customVoice0_6B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS CustomVoice 0.6B (bf16)",
    repoId: Qwen3TTSModelRepo.customVoice0_6B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 1_200_000_000,
    minimumMemoryBytes: 1_200_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.voiceDesign1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS VoiceDesign 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.voiceDesign1_7B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 3_400_000_000,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B_8bit.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (8-bit)",
    repoId: Qwen3TTSModelRepo.base1_7B_8bit.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 1_700_000_000,
    minimumMemoryBytes: 1_700_000_000
  ),
  // Deprecated: 4-bit variant has significant quality degradation.
  // Keep registered so existing cached copies can be migrated/deleted.
  // Excluded from UI/CLI model selection by default.
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B_4bit.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (4-bit) [Deprecated]",
    repoId: Qwen3TTSModelRepo.base1_7B_4bit.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 850_000_000,
    minimumMemoryBytes: 850_000_000,
    metadata: ["deprecated": "true"]
  ),
]

/// Module-level registration trigger.
///
/// This `let` is evaluated once (lazily) on first access, registering all
/// 7 Qwen3-TTS component descriptors with the SwiftAcervo Component Registry.
/// `VoxAltaModelManager.init()` references this to ensure registration happens
/// before any model loading or download call.
private let _registerQwen3TTSComponents: Void = {
  Acervo.register(qwen3TTSComponentDescriptors)
}()

// MARK: - VoxAltaModelManager

/// Actor responsible for the lifecycle of Qwen3-TTS models.
///
/// Manages loading models from HuggingFace via `TTSModelUtils`, caching the
/// loaded instance for reuse across multiple generation calls, and unloading
/// when switching models or reclaiming memory.
///
/// Because this is an actor, all access is serialized, preventing race conditions
/// when multiple callers attempt to load/unload simultaneously.
public actor VoxAltaModelManager {

  // MARK: - State

  /// The currently cached model instance, if any.
  private var cachedModel: (any SpeechGenerationModel)?

  /// The repository identifier of the currently loaded model.
  private var _currentModelRepo: String?

  // MARK: - Public API

  /// Whether a model is currently loaded and cached.
  public var isModelLoaded: Bool {
    cachedModel != nil
  }

  /// The HuggingFace repository identifier of the currently loaded model,
  /// or `nil` if no model is loaded.
  public var currentModelRepo: String? {
    _currentModelRepo
  }

  /// Whether legacy model migration has already been attempted this session.
  private var migrationAttempted = false

  /// Initializes an empty model manager with no model loaded.
  ///
  /// Triggers Acervo component registration on first instantiation via
  /// the module-level `_registerQwen3TTSComponents` lazy initializer.
  public init() {
    // Trigger lazy registration of all Qwen3-TTS ComponentDescriptors.
    _ = _registerQwen3TTSComponents
  }

  // MARK: - Acervo Integration

  /// Migrates models from the legacy cache path (`~/Library/Caches/intrusive-memory/Models/`)
  /// to Acervo's shared directory (`~/Library/SharedModels/`). Called once per session.
  public func migrateIfNeeded() {
    guard !migrationAttempted else { return }
    migrationAttempted = true
    do {
      let migrated = try Acervo.migrateFromLegacyPaths()
      if !migrated.isEmpty {
        FileHandle.standardError.write(
          Data(
            "Migrated \(migrated.count) model(s) to ~/Library/SharedModels/\n".utf8
          ))
      }
    } catch {
      FileHandle.standardError.write(
        Data(
          "Warning: model migration failed: \(error.localizedDescription)\n".utf8
        ))
    }
  }

  /// Checks whether a model is available in Acervo's shared directory.
  ///
  /// - Parameter modelId: The HuggingFace model identifier.
  /// - Returns: `true` if the model directory contains `config.json`.
  public nonisolated func isModelInAcervo(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  /// Loads a Qwen3-TTS model from the given HuggingFace repository.
  ///
  /// On the first call, the model is downloaded (if not already cached on disk)
  /// and loaded into memory. Subsequent calls with the same `repo` return the
  /// cached instance immediately. If called with a different `repo`, the
  /// currently loaded model is unloaded first.
  ///
  /// - Parameter repo: The HuggingFace model repository identifier
  ///   (e.g., `"mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"`).
  /// - Returns: The loaded `SpeechGenerationModel` instance.
  /// - Throws: `VoxAltaError.modelNotAvailable` if loading fails.
  public func loadModel(repo: String) async throws -> any SpeechGenerationModel {
    // One-time migration from legacy cache to Acervo shared directory
    migrateIfNeeded()

    // Return cached model if same repo is requested
    if let cached = cachedModel, _currentModelRepo == repo {
      return cached
    }

    // Unload current model if switching repos
    if cachedModel != nil {
      await unloadModel()
    }

    // Warn (but don't block) if memory looks tight — let macOS manage pressure.
    // Model size comes from the ComponentDescriptor registered at module init.
    if let modelRepo = Qwen3TTSModelRepo(rawValue: repo),
      let descriptor = Acervo.component(modelRepo.componentId)
    {
      await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
    }

    // Ensure the model's files are on disk via the Acervo Component Registry.
    // This replaces the implicit download-on-demand in TTSModelUtils.
    if let modelRepo = Qwen3TTSModelRepo(rawValue: repo) {
      try await Acervo.ensureComponentReady(modelRepo.componentId)
    }

    // Load via mlx-audio-swift's TTSModelUtils
    let model: any SpeechGenerationModel
    do {
      model = try await TTSModelUtils.loadModel(modelRepo: repo)
    } catch {
      throw VoxAltaError.modelNotAvailable(
        "Failed to load model from '\(repo)': \(error.localizedDescription)"
      )
    }

    // Cache the loaded model
    cachedModel = model
    _currentModelRepo = repo

    // Log Neural Accelerator status on M5
    let generation = AppleSiliconGeneration.current
    if generation.hasNeuralAccelerators {
      FileHandle.standardError.write(
        Data(
          "Neural Accelerators detected (\(generation.rawValue)) - MLX will auto-accelerate TTS inference (4× speedup on macOS 26.2+)\n"
            .utf8
        ))
    }

    return model
  }

  /// Loads a model using a well-known `Qwen3TTSModelRepo` enum case.
  ///
  /// Convenience wrapper around `loadModel(repo:)` that accepts the
  /// strongly-typed enum instead of a raw string.
  ///
  /// - Parameter modelRepo: The model variant to load.
  /// - Returns: The loaded `SpeechGenerationModel` instance.
  /// - Throws: `VoxAltaError.modelNotAvailable` if loading fails.
  public func loadModel(_ modelRepo: Qwen3TTSModelRepo) async throws -> any SpeechGenerationModel {
    try await loadModel(repo: modelRepo.rawValue)
  }

  /// Unloads the currently cached model and releases its memory.
  ///
  /// After calling this method, `isModelLoaded` returns `false` and
  /// `currentModelRepo` returns `nil`. Calling `unloadModel()` when
  /// no model is loaded is a no-op.
  public func unloadModel() async {
    cachedModel = nil
    _currentModelRepo = nil

    // Synchronize the GPU stream to ensure all in-flight Metal compute
    // from the previous model is complete, then release cached Metal buffers.
    // Without this, loading a new model can crash in AGX::ComputeContext
    // due to stale Metal command buffers from the previous model.
    await MemoryManager.shared.clearGPUCache()
  }

  // MARK: - Memory Validation

  /// Checks whether the system has sufficient available memory to load a model
  /// of the given size. Returns `false` (and logs a warning to stderr) if memory
  /// looks tight, but does **not** throw — macOS is capable of reclaiming memory
  /// from compressed, inactive, and cached pages on demand.
  ///
  /// Delegates to `MemoryManager.shared.softCheck(requiredBytes:)` after applying
  /// the 1.5x headroom multiplier for KV caches, intermediate activations, and
  /// the speech tokenizer during generation.
  ///
  /// - Parameter requiredBytes: The estimated memory footprint of the model in bytes.
  /// - Returns: `true` if available memory comfortably fits the model, `false` if it may be tight.
  @discardableResult
  public func checkMemory(forModelSizeBytes requiredBytes: Int) async -> Bool {
    let requiredWithHeadroom = UInt64(Double(requiredBytes) * Qwen3TTSModelSize.headroomMultiplier)
    let passed = await MemoryManager.shared.softCheck(requiredBytes: requiredWithHeadroom)

    if !passed {
      let availMB = await MemoryManager.shared.availableMemory / (1024 * 1024)
      let reqMB = requiredWithHeadroom / (1024 * 1024)
      FileHandle.standardError.write(
        Data(
          "Warning: Low memory — \(availMB) MB reclaimable vs \(reqMB) MB needed. macOS will manage swap if necessary.\n"
            .utf8
        ))
    }
    return passed
  }

  /// Legacy throwing validation — kept for callers that require a hard gate.
  ///
  /// Delegates to `MemoryManager.shared.hardValidate(requiredBytes:)` after applying
  /// the 1.5x headroom multiplier. Translates `PipelineError` to `VoxAltaError`.
  ///
  /// - Parameter requiredBytes: The estimated memory footprint of the model in bytes.
  /// - Throws: `VoxAltaError.insufficientMemory` if available memory is insufficient.
  public func validateMemory(forModelSizeBytes requiredBytes: Int) async throws {
    let requiredWithHeadroom = UInt64(Double(requiredBytes) * Qwen3TTSModelSize.headroomMultiplier)
    do {
      try await MemoryManager.shared.hardValidate(requiredBytes: requiredWithHeadroom)
    } catch {
      let available = await MemoryManager.shared.availableMemory
      throw VoxAltaError.insufficientMemory(
        available: Int(available),
        required: Int(requiredWithHeadroom)
      )
    }
  }

  /// Returns the total physical memory of the system in bytes.
  ///
  /// Delegates to `MemoryManager.shared.totalMemory`.
  public var totalPhysicalMemory: UInt64 {
    get async {
      await MemoryManager.shared.totalMemory
    }
  }

  /// Returns the currently available memory in bytes.
  ///
  /// Delegates to `MemoryManager.shared.availableMemory`.
  public var availableMemory: UInt64 {
    get async {
      await MemoryManager.shared.availableMemory
    }
  }
}
