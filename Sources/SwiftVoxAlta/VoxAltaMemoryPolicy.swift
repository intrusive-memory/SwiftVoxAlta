//
//  VoxAltaMemoryPolicy.swift
//  SwiftVoxAlta
//
//  Process-level MLX allocator policy for TTS hosts.
//

import Foundation
import MLX

/// Caps and drains the MLX buffer cache on behalf of an app hosting Qwen3-TTS.
///
/// ## Why this is here rather than in the host app
///
/// MLX's allocator keeps freed buffers in a cache so the next allocation is
/// cheap. Left alone, `MLX.Memory.cacheLimit` defaults to the device's Metal
/// **recommended working set** and `memoryLimit` to 1.5× that. Metal derives
/// those from the GPU, and knows nothing about the iOS jetsam footprint cap —
/// which is a fraction of device RAM and is what actually kills an app. The
/// result is an allocator happily holding gigabytes of cached buffers that
/// count in full against the process footprint.
///
/// Every host that loads a TTS model needs this cap, and only SwiftVoxAlta
/// links MLX. Exposing it here keeps consumers (Produciesta and friends) from
/// taking their own direct `mlx-swift` dependency purely to set one integer —
/// which would also give each of them an independent opinion on the pinned MLX
/// version.
///
/// ## Usage
///
/// Call ``applyRecommended()`` once at process start, before the first
/// generation:
///
/// ```swift
/// VoxAltaMemoryPolicy.applyRecommended()
/// ```
///
/// Under memory pressure prefer ``clearCache()`` — it returns cached buffers
/// while leaving model weights resident, so the next generation does not pay a
/// multi-gigabyte reload. Only fall back to `VoxAltaModelManager.unloadModel()`
/// when the pressure is critical.
public enum VoxAltaMemoryPolicy {

  /// The cache limit this platform should run with, in bytes.
  ///
  /// 128 MB on iOS/visionOS, where the process footprint cap is hard and every
  /// cached byte counts against it; 512 MB on macOS, where there is more room
  /// and a larger cache measurably helps throughput. Both are far below the
  /// Metal-derived default. mlx-audio-swift's own sample app and CLI pick
  /// values in this range (512 MB and 100 MB respectively).
  public static var recommendedCacheLimitBytes: Int {
    #if os(macOS)
      return 512 * 1024 * 1024
    #else
      return 128 * 1024 * 1024
    #endif
  }

  /// Apply ``recommendedCacheLimitBytes``.
  ///
  /// Idempotent and safe to call from any thread — `MLX.Memory` serializes its
  /// own state internally.
  ///
  /// - Returns: The cache limit that was in effect before this call, in bytes.
  @discardableResult
  public static func applyRecommended() -> Int {
    setCacheLimit(recommendedCacheLimitBytes)
  }

  /// Set the MLX buffer-cache limit.
  ///
  /// - Parameter bytes: The new limit. `0` disables caching entirely, which is
  ///   what makes a subsequent ``clearCache()`` return memory to the OS rather
  ///   than to MLX's own pool.
  /// - Returns: The previous limit, so a caller can restore it.
  @discardableResult
  public static func setCacheLimit(_ bytes: Int) -> Int {
    let previous = Memory.cacheLimit
    Memory.cacheLimit = bytes
    return previous
  }

  /// The current MLX buffer-cache limit, in bytes.
  public static var cacheLimitBytes: Int {
    Memory.cacheLimit
  }

  /// Bytes MLX currently holds in live allocations.
  public static var activeBytes: Int {
    Memory.activeMemory
  }

  /// Bytes MLX currently holds in its buffer cache.
  public static var cachedBytes: Int {
    Memory.cacheMemory
  }

  /// Release MLX's cached buffers **to the OS**, keeping model weights loaded.
  ///
  /// A bare `Memory.clearCache()` hands buffers back to MLX's pool, not the
  /// system, so process footprint barely moves. Dropping the limit to zero
  /// first forces a real release; the prior limit is then restored. This is the
  /// same drain `VoxAltaModelManager.unloadModel()` performs, minus the unload.
  ///
  /// Prefer this over unloading when responding to a non-critical memory
  /// warning: it is cheap, and the next generation does not reload the model.
  public static func clearCache() {
    let previous = Memory.cacheLimit
    Memory.cacheLimit = 0
    Memory.clearCache()
    Memory.cacheLimit = previous
  }
}
