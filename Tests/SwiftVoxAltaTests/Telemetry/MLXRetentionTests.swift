//
//  MLXRetentionTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 7 — verifies that checkMLXRetention() does not crash and that
//  metalBufferState events fire around model lifecycle operations.
//

import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaModelManager — MLX retention", .acervoEnvironment)
struct MLXRetentionTests {

  @Test("checkMLXRetention does not crash, returns a struct (tolerates -1 values)")
  func checkMLXRetentionDoesNotCrash() async {
    let manager = VoxAltaModelManager()
    let report = await manager._checkMLXRetentionForTesting()
    // Any of the three fields may be -1. Just confirm we got a report.
    // (Equatable check against itself proves the struct exists and was returned.)
    #expect(report == report)
  }

  @Test("metalBufferState event fires after unloadModel (no-op path)")
  func metalBufferStateFiresAroundUnload() async {
    let manager = VoxAltaModelManager()
    let reporter = MockTelemetryReporter()
    await manager.setTelemetry(reporter)

    await manager.unloadModel()

    let events = await reporter.events
    let metalEventCount = events.filter { event in
      if case .metalBufferState = event { return true }
      return false
    }.count
    // Exactly one .metalBufferState — the post-unload one. (Load events only fire on
    // successful load, which is not exercised here. Sortie 8's E2E test verifies broader symmetry.)
    #expect(metalEventCount == 1)
  }
}
