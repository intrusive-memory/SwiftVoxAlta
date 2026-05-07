//
//  VoxAltaTelemetryEvent.swift
//  SwiftVoxAlta
//
//  Foundation event type for the VoxAlta telemetry pipeline.
//

import Foundation

/// Lifecycle events emitted by the VoxAlta provider and model manager so that
/// external consumers (e.g. Produciesta) can observe model load/unload
/// behaviour, voice cache growth, and Metal buffer state without coupling to
/// SwiftVoxAlta's internals. These events are consumer-facing observability
/// hooks: a `VoxAltaTelemetryReporter` attached via
/// `VoxAltaVoiceProvider.setTelemetry(_:)` receives one of these enum values
/// per significant lifecycle transition. Events are values — `Sendable` and
/// `Equatable` — so consumers can buffer, compare, and round-trip them in
/// tests without bespoke equality logic.
public enum VoxAltaTelemetryEvent: Sendable, Equatable {
  case modelLoadStart(repo: String, cacheHit: Bool)
  case modelLoadComplete(repo: String, sizeMB: Double)
  case modelUnloadStart(loaded: Bool, sizeMB: Double)
  case modelUnloadComplete(freed: Double, processMemoryMB: Double)
  case voiceCacheGrowth(entriesCount: Int, totalMB: Double)
  case metalBufferState(allocatedMB: Double, peakMB: Double)
}
