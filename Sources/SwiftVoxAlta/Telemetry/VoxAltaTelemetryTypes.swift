//
//  VoxAltaTelemetryTypes.swift
//  SwiftVoxAlta
//
//  Value types carried inside or alongside `VoxAltaTelemetryEvent`.
//

import Foundation

/// Snapshot of the voice cache's current contents, returned by
/// `VoxAltaVoiceCache.reportState()` and used by the provider to populate
/// `VoxAltaTelemetryEvent.voiceCacheGrowth` events. `topVoicesBySize` is the
/// largest few entries by clone-prompt byte count, useful for diagnosing
/// runaway cache growth across an episode.
public struct VoiceCacheTelemetry: Sendable, Equatable {
  public let entriesCount: Int
  public let totalBytesCached: Int
  public let topVoicesBySize: [TopVoice]

  /// One entry in `VoiceCacheTelemetry.topVoicesBySize`.
  public struct TopVoice: Sendable, Equatable {
    public let voiceId: String
    public let bytes: Int

    public init(voiceId: String, bytes: Int) {
      self.voiceId = voiceId
      self.bytes = bytes
    }
  }

  public init(entriesCount: Int, totalBytesCached: Int, topVoicesBySize: [TopVoice]) {
    self.entriesCount = entriesCount
    self.totalBytesCached = totalBytesCached
    self.topVoicesBySize = topVoicesBySize
  }
}

/// Best-effort snapshot of MLX/Metal retention state at the moment of
/// inspection. Any field may be `-1` (or `-1.0` for the `Double`) when the
/// corresponding value is not exposed by the public mlx-swift / mlx-audio
/// API surface; consumers should treat sentinel `-1` values as "unknown" and
/// skip them when computing deltas. See Sortie 7's design notes for the
/// rationale: SwiftVoxAlta will not reach into private MLX internals to fill
/// these fields, so the sentinel is a deliberate, durable contract.
public struct MLXRetentionReport: Sendable, Equatable {
  public let activeArrayCount: Int
  public let metalHeapSizeMB: Double
  public let modelRegistrySize: Int

  public init(activeArrayCount: Int, metalHeapSizeMB: Double, modelRegistrySize: Int) {
    self.activeArrayCount = activeArrayCount
    self.metalHeapSizeMB = metalHeapSizeMB
    self.modelRegistrySize = modelRegistrySize
  }
}
