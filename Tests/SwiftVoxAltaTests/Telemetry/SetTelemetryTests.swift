//
//  SetTelemetryTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 4 — verifies that wiring a reporter produces no events on its own.
//

import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaVoiceProvider — setTelemetry", .acervoEnvironment)
struct SetTelemetryTests {
  @Test("Setting a reporter does not produce any events on its own")
  func setTelemetryProducesNoEvents() async {
    let provider = VoxAltaVoiceProvider()
    let reporter = MockTelemetryReporter()
    await provider.setTelemetry(reporter)
    let events = await reporter.events
    #expect(events.isEmpty)
  }

  @Test("Passing nil to setTelemetry does not crash")
  func setTelemetryNilDoesNotCrash() async {
    let provider = VoxAltaVoiceProvider()
    await provider.setTelemetry(nil)
    // Reaching this point without trapping is the assertion.
    #expect(Bool(true))
  }
}
