//
//  VoxAltaModelManager.swift
//  SwiftVoxAlta
//
//  Actor managing Qwen3-TTS model lifecycle via mlx-audio-swift.
//  Handles model loading, caching, unloading, and memory validation.
//

import Foundation
import MLX
import MLXAudioCore
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
  /// Equal to `Acervo.slugify(rawValue)`, which is also the CDN slug under which
  /// the model's manifest is served (`<R2_PUBLIC_URL>/models/<slug>/manifest.json`).
  /// Keeping component ID == slugified repo ID == CDN slug eliminates triple-naming
  /// between SwiftVoxAlta, mlx-audio-swift, and the CDN.
  public var componentId: String {
    Acervo.slugify(rawValue)
  }
}

/// All 7 Qwen3-TTS component descriptors (6 active + 1 deprecated).
///
/// Bare descriptors — no `files:` or `estimatedSizeBytes:` declared. SwiftAcervo
/// auto-hydrates each one from the CDN manifest on first call to
/// `ensureComponentReady`, so the file list and total size are always whatever
/// the published manifest says, never a stale local mirror. `minimumMemoryBytes`
/// stays here because it is a VoxAlta policy decision, not model metadata.
private let qwen3TTSComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base0_6B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 0.6B (bf16)",
    repoId: Qwen3TTSModelRepo.base0_6B.rawValue,
    minimumMemoryBytes: 1_200_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.customVoice1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS CustomVoice 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.customVoice1_7B.rawValue,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.customVoice0_6B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS CustomVoice 0.6B (bf16)",
    repoId: Qwen3TTSModelRepo.customVoice0_6B.rawValue,
    minimumMemoryBytes: 1_200_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.voiceDesign1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS VoiceDesign 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.voiceDesign1_7B.rawValue,
    minimumMemoryBytes: 3_400_000_000
  ),
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B_8bit.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (8-bit)",
    repoId: Qwen3TTSModelRepo.base1_7B_8bit.rawValue,
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

  /// Wrapper that lets a non-Sendable `SpeechGenerationModel` cross the
  /// nonisolated `Task` boundary used for single-flight load coordination.
  /// The model is only ever observed from inside this actor, so unchecked
  /// Sendable is safe.
  private struct LoadedModelBox: @unchecked Sendable {
    let model: any SpeechGenerationModel
  }

  /// In-flight load coordination. Concurrent callers requesting the same
  /// repo await this Task instead of each starting their own load.
  ///
  /// Without this, actor reentrancy across the awaits inside `loadModel`
  /// (e.g. `Acervo.ensureComponentReady`) lets every concurrent caller pass
  /// the cache check before any one finishes, multiplying the model's memory
  /// footprint by N. With N envelope-driven calls each mmapping a ~4 GB
  /// model, virtual footprint reaches tens of GB and the OS reclaims us.
  private var inFlightLoad: (repo: String, task: Task<LoadedModelBox, Error>)?

  /// Number of times `_performLoad` has actually executed. Used by tests to
  /// verify that concurrent `loadModel` calls coalesce onto one underlying
  /// load rather than each running their own.
  internal private(set) var performLoadInvocationCount: Int = 0

  /// Test-only helper. Wraps `loadModel(repo:)` and discards the non-Sendable
  /// result inside this actor's isolation, exposing only the success/throw to
  /// nonisolated callers. Tests use this to drive concurrent loads without
  /// having to import MLXAudioTTS just to satisfy Sendable on `any
  /// SpeechGenerationModel`.
  internal func _loadModelDiscardingResult(repo: String) async throws {
    _ = try await loadModel(repo: repo)
  }

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

  /// Initializes an empty model manager with no model loaded.
  ///
  /// Triggers Acervo component registration on first instantiation via
  /// the module-level `_registerQwen3TTSComponents` lazy initializer.
  public init() {
    // Trigger lazy registration of all Qwen3-TTS ComponentDescriptors.
    _ = _registerQwen3TTSComponents
  }

  // MARK: - Acervo Integration

  /// Checks whether a model is available in Acervo's shared directory.
  ///
  /// - Parameter modelId: The HuggingFace model identifier.
  /// - Returns: `true` if the model directory contains `config.json`.
  public nonisolated func isModelInAcervo(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  /// Validates a component's files via SwiftAcervo and then loads the model.
  ///
  /// `withComponentAccess`'s closure is synchronous (`@Sendable (ComponentHandle) throws -> T`),
  /// so the async `TTSModelUtils.loadModel` cannot run inside it. The closure is therefore used
  /// purely to trigger SwiftAcervo's file-presence and checksum validation on entry; the load
  /// runs immediately afterward. There is a narrow TOCTOU window between closure exit and load
  /// — closing it cleanly requires an async-closure overload of `withComponentAccess` upstream
  /// in SwiftAcervo (see ACERVO_AUDIT.md, Finding 2). For now the `AcervoError` switch below
  /// surfaces any validation failure with an actionable message.
  ///
  /// - Parameter componentId: The Acervo component ID for the model.
  /// - Parameter repo: The HuggingFace repository identifier.
  /// - Returns: The loaded `SpeechGenerationModel` instance.
  /// - Throws: `VoxAltaError.modelNotAvailable` with a typed message derived
  ///   from the underlying `AcervoError` case when the failure is from Acervo.
  private func _loadModelWithComponentValidation(
    componentId: String,
    repo: String
  ) async throws -> any SpeechGenerationModel {
    do {
      try await AcervoManager.shared.withComponentAccess(componentId) { @Sendable _ in
        // Validation happens on closure entry (file presence + checksums).
        // The async load must run outside this sync closure.
        ()
      }
      // Explicit modelType avoids mlx-audio-swift's inferModelType, which checks
      // for "qwen3_tts" (underscore) but the HF repo uses "qwen3-tts" (hyphen)
      // and would mis-route to the non-TTS Qwen3 LLM path.
      return try await TTSModelUtils.loadModel(modelRepo: repo, modelType: "qwen3_tts")
    } catch let error as AcervoError {
      switch error {
      case .modelNotFound(let id):
        throw VoxAltaError.modelNotAvailable("Model '\(id)' not found on CDN")
      case .integrityCheckFailed(let file, _, _):
        throw VoxAltaError.modelNotAvailable(
          "File '\(file)' failed SHA-256 verification; re-download required"
        )
      case .downloadSizeMismatch(let fileName, let expected, let actual):
        throw VoxAltaError.modelNotAvailable(
          "File '\(fileName)' size mismatch (\(actual) vs \(expected))"
        )
      case .componentNotRegistered(let id):
        throw VoxAltaError.modelNotAvailable(
          "Unknown component '\(id)' (internal bug: forgot to register?)"
        )
      case .componentNotHydrated(let id):
        throw VoxAltaError.modelNotAvailable(
          "Component '\(id)' needs hydration before sync inspection"
        )
      case .offlineModeActive:
        throw VoxAltaError.modelNotAvailable(
          "ACERVO_OFFLINE=1 — refusing CDN fetch; model not present locally"
        )
      case .fileNotInManifest(let fileName, let modelId):
        throw VoxAltaError.modelNotAvailable(
          "Model '\(modelId)' does not include '\(fileName)' in its CDN manifest"
        )
      case .manifestIntegrityFailed:
        throw VoxAltaError.modelNotAvailable(
          "Manifest checksum mismatch; CDN copy may be corrupt"
        )
      case .manifestDownloadFailed(let statusCode):
        throw VoxAltaError.modelNotAvailable(
          "Manifest download failed (HTTP \(statusCode))"
        )
      default:
        throw VoxAltaError.modelNotAvailable(
          "SwiftAcervo error: \(error.localizedDescription)"
        )
      }
    } catch {
      throw VoxAltaError.modelNotAvailable(
        "Failed to load model from '\(repo)': \(error.localizedDescription)"
      )
    }
  }

  /// Loads a Qwen3-TTS model from the given HuggingFace repository.
  ///
  /// On the first call, the model is downloaded (if not already cached on disk)
  /// and loaded into memory. Subsequent calls with the same `repo` return the
  /// cached instance immediately. If called with a different `repo`, the
  /// currently loaded model is unloaded first.
  ///
  /// File access is protected via v2 Acervo access patterns: `ensureComponentReady()`
  /// ensures downloads, then `_loadModelWithComponentValidation()` validates file presence
  /// and checksums before loading.
  ///
  /// - Parameter repo: The HuggingFace model repository identifier
  ///   (e.g., `"mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"`).
  /// - Returns: The loaded `SpeechGenerationModel` instance.
  /// - Throws: `VoxAltaError.modelNotAvailable` if loading fails.
  public func loadModel(repo: String) async throws -> any SpeechGenerationModel {
    // Cache hit: same repo, already loaded. Return silently — cache hits are
    // not loads, and emitting load telemetry on every hit produced ~117/118
    // events of pure noise on a 56-element run (see FIX_ME.md #1).
    if let cached = cachedModel, _currentModelRepo == repo {
      return cached
    }

    // Coalesce concurrent callers requesting the same repo onto a single
    // in-flight load. See `inFlightLoad` for the rationale. Joining is also
    // not a fresh load, so no telemetry here either.
    if let inFlight = inFlightLoad, inFlight.repo == repo {
      return try await inFlight.task.value.model
    }

    await capture(.modelLoadStart(repo: repo, cacheHit: false))

    let loadTask = Task<LoadedModelBox, Error> { [weak self] in
      guard let self = self else {
        throw VoxAltaError.modelNotAvailable("VoxAltaModelManager deallocated during load")
      }
      return try await self._performLoad(repo: repo)
    }
    inFlightLoad = (repo: repo, task: loadTask)

    do {
      let model = try await loadTask.value.model
      cachedModel = model
      _currentModelRepo = repo
      inFlightLoad = nil
      applyMLXTelemetryToCachedModel()

      // Log Neural Accelerator status on M5
      let generation = AppleSiliconGeneration.current
      if generation.hasNeuralAccelerators {
        FileHandle.standardError.write(
          Data(
            "Neural Accelerators detected (\(generation.rawValue)) - MLX will auto-accelerate TTS inference (4× speedup on macOS 26.2+)\n"
              .utf8
          ))
      }
      await capture(.modelLoadComplete(repo: repo, sizeMB: estimateModelMemoryUsage()))
      let mlxReport = checkMLXRetention()
      await capture(.metalBufferState(allocatedMB: mlxReport.metalHeapSizeMB, peakMB: -1.0))
      // peak unavailable from public MLX API
      return model
    } catch {
      inFlightLoad = nil
      throw error
    }
  }

  /// Runs the actual model load. Extracted from `loadModel(repo:)` so the
  /// load body can run inside a single-flight `Task` that coalesces
  /// concurrent callers. Returns a `LoadedModelBox` so the result can cross
  /// the nonisolated Task boundary (the model itself is non-Sendable).
  private func _performLoad(repo: String) async throws -> LoadedModelBox {
    performLoadInvocationCount += 1

    // Unload current model if switching repos
    if cachedModel != nil {
      await unloadModel()
    }

    // Resolve the component ID for this model variant
    guard let modelRepo = Qwen3TTSModelRepo(rawValue: repo) else {
      throw VoxAltaError.modelNotAvailable(
        "Unknown Qwen3-TTS repository: '\(repo)'"
      )
    }

    let componentId = modelRepo.componentId

    // Warn (but don't block) if memory looks tight — let macOS manage pressure.
    // Model size comes from the ComponentDescriptor registered at module init.
    if let descriptor = Acervo.component(componentId) {
      await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
    }

    // Step 1: Ensure the model's files are downloaded via Acervo Component Registry.
    try await Acervo.ensureComponentReady(componentId)

    // Step 2: Load the model with v2 access patterns (file presence and checksums validated).
    let model = try await _loadModelWithComponentValidation(
      componentId: componentId,
      repo: repo
    )
    return LoadedModelBox(model: model)
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
    let wasLoaded = cachedModel != nil
    let preSizeMB = estimateModelMemoryUsage()
    let memBefore = getCurrentProcessMemory()
    await capture(.modelUnloadStart(loaded: wasLoaded, sizeMB: preSizeMB))

    // Drain the MLX allocator instead of merely clearing its cache.
    //
    // 1. Synchronize the GPU stream FIRST, while the model is still alive,
    //    so any in-flight Metal command buffers retire before we drop
    //    references. Without this, AGX::ComputeContext can hold stale buffers
    //    that reference the just-deallocated model (crashes the next load).
    Stream.gpu.synchronize()

    // 2. Drop strong references to the model's MLXArrays.
    cachedModel = nil
    _currentModelRepo = nil

    // 3. Force MLX to actually release reclaimed buffers to the OS rather
    //    than parking them in its buffer pool. The pool defaults to ~1.5x
    //    the device's recommended working set; without dropping the limit
    //    to 0 first, `clearCache()` returns memory to the pool, not the OS,
    //    and the Metal heap stays pinned at ~4.3 GB after unload
    //    (see FIX_ME.md #2). We restore the prior limit afterward so
    //    subsequent loads don't pay alloc/free per intermediate buffer.
    let priorCacheLimit = Memory.cacheLimit
    Memory.cacheLimit = 0
    await MemoryManager.shared.clearGPUCache()
    Stream.gpu.synchronize()
    Memory.cacheLimit = priorCacheLimit

    let memAfter = getCurrentProcessMemory()
    let freed = max(0.0, memBefore - memAfter)
    await capture(.modelUnloadComplete(freed: freed, processMemoryMB: memAfter))
    let mlxReport = checkMLXRetention()
    await capture(.metalBufferState(allocatedMB: mlxReport.metalHeapSizeMB, peakMB: -1.0))
    // peak unavailable from public MLX API
  }

  // MARK: - Memory Validation

  /// Returns the approximate memory footprint of the currently loaded model in megabytes.
  ///
  /// The estimate is based on a substring match against the loaded model's repository identifier:
  /// - `"1.7B"` → `3400.0` MB
  /// - `"0.6B"` → `1200.0` MB
  /// - `nil` repo (no model loaded) or unrecognized string → `0.0`
  ///
  /// Use this for **deltas and ordering signals**, not precise accounting.
  /// Returns `0.0` when no model is loaded or the repo string is unrecognized.
  internal func estimateModelMemoryUsage() -> Double {
    guard let repo = _currentModelRepo else { return 0.0 }
    if repo.contains("1.7B") { return 3400.0 }
    if repo.contains("0.6B") { return 1200.0 }
    return 0.0
  }

  /// Test-only seam: sets the actor's `_currentModelRepo` without going through
  /// `loadModel`. Used by `EstimateModelMemoryTests` to exercise the substring
  /// matching in `estimateModelMemoryUsage()` without disk/network dependency.
  internal func _setCurrentModelRepoForTesting(_ repo: String?) {
    _currentModelRepo = repo
  }

  /// Test-only seam: seeds the actor's cache state with a stub model and repo
  /// so cache-hit branches can be exercised without requiring a real on-disk
  /// model. Used by `LoadUnloadTelemetryTests` to verify cache-hit telemetry
  /// suppression (FIX_ME.md #1).
  internal func _setCachedModelForTesting(
    _ model: (any SpeechGenerationModel)?,
    repo: String?
  ) {
    cachedModel = model
    _currentModelRepo = repo
  }

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

  // MARK: - Telemetry

  /// Optional reporter to receive lifecycle events. Set via `setTelemetry`.
  /// A nil reporter is a no-op — `capture` never blocks the caller.
  private var telemetry: (any VoxAltaTelemetryReporter)?

  /// Optional MLXAudio reporter forwarded to the active Qwen3TTS model.
  /// Distinct from `telemetry` (VoxAlta-level events).
  private var mlxAudioTelemetry: (any MLXAudioTelemetryReporter)?

  /// Attaches or detaches a telemetry reporter. Pass `nil` to disable.
  public func setTelemetry(_ reporter: (any VoxAltaTelemetryReporter)?) {
    self.telemetry = reporter
  }

  /// Attaches or detaches an MLXAudio telemetry reporter. Applied immediately
  /// to any currently-cached model, and to every model loaded thereafter.
  public func setMLXTelemetry(_ reporter: (any MLXAudioTelemetryReporter)?) {
    self.mlxAudioTelemetry = reporter
    if let qwenModel = cachedModel as? Qwen3TTSModel {
      qwenModel.setTelemetry(reporter)
    }
  }

  /// Applies the current MLXAudio reporter (if any) to a freshly loaded model.
  /// Called from `loadModel(repo:)` after `cachedModel` is bound.
  private func applyMLXTelemetryToCachedModel() {
    guard let reporter = mlxAudioTelemetry,
      let qwenModel = cachedModel as? Qwen3TTSModel
    else { return }
    qwenModel.setTelemetry(reporter)
  }

  /// Forwards a telemetry event to the attached reporter, if any.
  /// Used by Sorties 5, 6, 7 to emit lifecycle events without each call site
  /// needing nil-checks.
  internal func capture(_ event: VoxAltaTelemetryEvent) async {
    await telemetry?.capture(event)
  }

  /// Probes the public MLX/Metal API surface for best-effort retention metrics.
  ///
  /// `activeArrayCount` has no public counter in the mlx-swift API; returns `-1`.
  /// `metalHeapSizeMB` is derived from `Memory.activeMemory` (mlx-swift public API).
  /// `modelRegistrySize` is always `-1` — SwiftVoxAlta has no model registry;
  /// placeholder for forward compatibility.
  private func checkMLXRetention() -> MLXRetentionReport {
    // activeArrayCount: no public array-count counter in mlx-swift → -1
    let activeArrayCount: Int = -1

    // metalHeapSizeMB: derived from MLX.Memory.activeMemory (bytes) / 1024 / 1024
    let metalHeapSizeMB: Double = Double(Memory.activeMemory) / 1024.0 / 1024.0

    // SwiftVoxAlta has no model registry; placeholder for forward compatibility.
    let modelRegistrySize: Int = -1

    return MLXRetentionReport(
      activeArrayCount: activeArrayCount,
      metalHeapSizeMB: metalHeapSizeMB,
      modelRegistrySize: modelRegistrySize
    )
  }

  internal func _checkMLXRetentionForTesting() -> MLXRetentionReport {
    checkMLXRetention()
  }
}
