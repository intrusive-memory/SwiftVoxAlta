//
//  MockTelemetryReporterTests.swift
//  SwiftVoxAltaTests
//
//  Smoke test for the test-only `MockTelemetryReporter` and round-trip of
//  every `VoxAltaTelemetryEvent` variant through the protocol.
//

import Testing

@testable import SwiftVoxAlta

@Suite("MockTelemetryReporter — smoke", .acervoEnvironment)
struct MockTelemetryReporterTests {
  @Test("Captures all six event variants in order with Equatable round-trip")
  func capturesAllSixVariants() async {
    let reporter = MockTelemetryReporter()
    let events: [VoxAltaTelemetryEvent] = [
      .modelLoadStart(repo: "test/repo", cacheHit: false),
      .modelLoadComplete(repo: "test/repo", sizeMB: 1234.5),
      .modelUnloadStart(loaded: true, sizeMB: 1234.5),
      .modelUnloadComplete(freed: 1100.0, processMemoryMB: 200.0),
      .voiceCacheGrowth(entriesCount: 3, totalMB: 0.5),
      .metalBufferState(allocatedMB: 500.0, peakMB: -1.0),
    ]
    for event in events {
      await reporter.capture(event)
    }
    let recorded = await reporter.events
    #expect(recorded == events)
  }
}
