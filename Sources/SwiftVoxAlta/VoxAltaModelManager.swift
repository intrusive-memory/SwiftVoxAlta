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

// MARK: - Approximate Model Sizes

/// Approximate on-disk/memory sizes for known Qwen3-TTS model variants.
/// Used by `validateMemory` to check whether the system has enough RAM
/// before attempting to load a model.
public enum Qwen3TTSModelSize {
    /// Approximate byte sizes for known model repos.
    /// These are conservative estimates of the memory footprint once loaded.
    public static let knownSizes: [String: Int] = [
        // bf16 variants
        "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16": 3_400_000_000,
        "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16": 3_400_000_000,
        "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16": 1_200_000_000,
        "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16": 3_400_000_000,
        "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16": 1_200_000_000,
        // 8-bit quantized variants
        "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit": 1_700_000_000,
        "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit": 1_700_000_000,
        // 4-bit quantized variants
        "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit": 850_000_000,
        "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit": 850_000_000,
    ]

    /// The memory headroom multiplier applied to estimated model sizes.
    /// Models need additional memory for KV caches, intermediate activations,
    /// and the speech tokenizer during generation.
    public static let headroomMultiplier: Double = 1.5
}

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
    public init() {}

    // MARK: - Acervo Integration

    /// Migrates models from the legacy cache path (`~/Library/Caches/intrusive-memory/Models/`)
    /// to Acervo's shared directory (`~/Library/SharedModels/`). Called once per session.
    public func migrateIfNeeded() {
        guard !migrationAttempted else { return }
        migrationAttempted = true
        do {
            let migrated = try Acervo.migrateFromLegacyPaths()
            if !migrated.isEmpty {
                FileHandle.standardError.write(Data(
                    "Migrated \(migrated.count) model(s) to ~/Library/SharedModels/\n".utf8
                ))
            }
        } catch {
            FileHandle.standardError.write(Data(
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
            unloadModel()
        }

        // Warn (but don't block) if memory looks tight — let macOS manage pressure
        if let estimatedSize = Qwen3TTSModelSize.knownSizes[repo] {
            checkMemory(forModelSizeBytes: estimatedSize)
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
            FileHandle.standardError.write(Data(
                "Neural Accelerators detected (\(generation.rawValue)) - MLX will auto-accelerate TTS inference (4× speedup on macOS 26.2+)\n".utf8
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
    public func unloadModel() {
        cachedModel = nil
        _currentModelRepo = nil
    }

    // MARK: - Memory Validation

    /// Checks whether the system has sufficient available memory to load a model
    /// of the given size. Returns `false` (and logs a warning to stderr) if memory
    /// looks tight, but does **not** throw — macOS is capable of reclaiming memory
    /// from compressed, inactive, and cached pages on demand.
    ///
    /// - Parameter requiredBytes: The estimated memory footprint of the model in bytes.
    /// - Returns: `true` if available memory comfortably fits the model, `false` if it may be tight.
    @discardableResult
    public func checkMemory(forModelSizeBytes requiredBytes: Int) -> Bool {
        let available = Self.queryAvailableMemory()
        let requiredWithHeadroom = Int(Double(requiredBytes) * Qwen3TTSModelSize.headroomMultiplier)

        if available < requiredWithHeadroom {
            let availMB = available / (1024 * 1024)
            let reqMB = requiredWithHeadroom / (1024 * 1024)
            FileHandle.standardError.write(Data(
                "Warning: Low memory — \(availMB) MB reclaimable vs \(reqMB) MB needed. macOS will manage swap if necessary.\n".utf8
            ))
            return false
        }
        return true
    }

    /// Legacy throwing validation — kept for callers that require a hard gate.
    ///
    /// - Parameter requiredBytes: The estimated memory footprint of the model in bytes.
    /// - Throws: `VoxAltaError.insufficientMemory` if available memory is insufficient.
    public func validateMemory(forModelSizeBytes requiredBytes: Int) throws {
        let available = Self.queryAvailableMemory()
        let requiredWithHeadroom = Int(Double(requiredBytes) * Qwen3TTSModelSize.headroomMultiplier)

        guard available >= requiredWithHeadroom else {
            throw VoxAltaError.insufficientMemory(
                available: available,
                required: requiredWithHeadroom
            )
        }
    }

    /// Returns the total physical memory of the system in bytes.
    ///
    /// Useful for display in configuration UI to show total vs. available memory.
    public var totalPhysicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Returns the currently available memory in bytes.
    ///
    /// Uses Mach VM statistics to estimate free + purgeable memory.
    public var availableMemory: UInt64 {
        UInt64(Self.queryAvailableMemory())
    }

    /// Query reclaimable memory using Mach VM statistics.
    ///
    /// Includes free, purgeable, inactive, and speculative pages — all of which
    /// macOS can reclaim on demand without terminating processes. This gives a
    /// realistic picture of what's actually available for large allocations,
    /// rather than just the "free" count shown by Activity Monitor.
    private nonisolated static func queryAvailableMemory() -> Int {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            // Fallback: use total physical memory as a rough estimate
            return Int(ProcessInfo.processInfo.physicalMemory)
        }
        // Use sysctl to get page size (vm_kernel_page_size is unavailable on macOS 26)
        let pageSize = Self.systemPageSize
        let free = Int(stats.free_count) * pageSize
        let inactive = Int(stats.inactive_count) * pageSize
        let purgeable = Int(stats.purgeable_count) * pageSize
        let speculative = Int(stats.speculative_count) * pageSize
        return free + inactive + purgeable + speculative
    }

    /// System page size obtained via sysctl, avoiding deprecated vm_kernel_page_size.
    private nonisolated static var systemPageSize: Int {
        var pageSize: Int = 0
        var size = MemoryLayout<Int>.size
        sysctlbyname("hw.pagesize", &pageSize, &size, nil, 0)
        return pageSize > 0 ? pageSize : 16384  // Default to 16KB (Apple Silicon)
    }
}
