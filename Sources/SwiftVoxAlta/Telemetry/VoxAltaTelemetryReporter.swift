//
//  VoxAltaTelemetryReporter.swift
//  SwiftVoxAlta
//
//  Public protocol consumers implement to receive VoxAlta lifecycle events.
//

import Foundation

/// Sink for `VoxAltaTelemetryEvent` values. Consumers (e.g. Produciesta)
/// implement this protocol to receive lifecycle events from the VoxAlta
/// provider and model manager — model load/unload, voice cache growth, and
/// Metal buffer state. A `nil` reporter is treated as a no-op by the
/// provider, so attaching telemetry is strictly opt-in and never blocks
/// callers that don't care.
///
/// `capture(_:)` is `async` because reporters may perform I/O — writing to a
/// log file, pushing to an analytics backend, or forwarding into another
/// actor — and the provider awaits the call to preserve event ordering.
public protocol VoxAltaTelemetryReporter: Sendable {
  func capture(_ event: VoxAltaTelemetryEvent) async
}
