//
//  EndToEndContractTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 8 — end-to-end protocol contract test.
//  Verifies that `VoxAltaVoiceProvider` + `VoxAltaModelManager` emit the
//  documented event sequence for the voice-cache and model-unload lifecycle
//  phases as observed by a Produciesta-style telemetry consumer.
//
//  This test does NOT call `generateAudio` or trigger any actual model load
//  (which would require a 3.4GB cached model on disk). It exercises:
//    Phase 1: voice-cache mutations → .voiceCacheGrowth events.
//    Phase 2: unloadModel() no-op → .modelUnloadStart + .modelUnloadComplete
//             + .metalBufferState events.
//

import Foundation
import Testing

@testable import SwiftVoxAlta

@Suite("Produciesta event-stream contract — end-to-end", .acervoEnvironment)
struct EndToEndContractTests {

  @Test("Provider + manager emit the documented event sequence")
  func produciestaContractEventStream() async {
    let provider = VoxAltaVoiceProvider()
    let reporter = MockTelemetryReporter()
    await provider.setTelemetry(reporter)

    // Phase 1 — voice-cache mutations.
    // loadVoice emits .voiceCacheGrowth(entriesCount: 1, totalMB: ~0.002).
    // unloadAllVoices emits .voiceCacheGrowth(entriesCount: 0, totalMB: 0.0).
    await provider.loadVoice(id: "TEST_E2E", clonePromptData: Data(repeating: 0xAB, count: 2048))
    await provider.unloadAllVoices()

    // Phase 2 — model-lifecycle no-op.
    // unloadModel() is called directly on the manager via the provider's internal
    // manager reference. The provider exposes the manager as `private`, so we
    // use the pattern established in LoadUnloadTelemetryTests: instantiate a
    // VoxAltaModelManager, attach the same reporter, and call unloadModel()
    // directly. This matches the model-manager contract the provider delegates to.
    let manager = VoxAltaModelManager()
    await manager.setTelemetry(reporter)
    await manager.unloadModel()

    let events = await reporter.events

    // MARK: - Phase 1 assertions: voice-cache growth sequence

    // Find the first .voiceCacheGrowth with entriesCount == 1 (after loadVoice).
    var firstGrowthIndex: Int? = nil
    var zeroGrowthIndex: Int? = nil
    for (i, event) in events.enumerated() {
      if case .voiceCacheGrowth(let count, _) = event {
        if firstGrowthIndex == nil && count == 1 {
          firstGrowthIndex = i
        } else if firstGrowthIndex != nil && zeroGrowthIndex == nil && count == 0 {
          zeroGrowthIndex = i
        }
      }
    }

    #expect(
      firstGrowthIndex != nil, "Expected a .voiceCacheGrowth(entriesCount: 1) event after loadVoice"
    )
    #expect(
      zeroGrowthIndex != nil,
      "Expected a .voiceCacheGrowth(entriesCount: 0) event after unloadAllVoices")
    if let f = firstGrowthIndex, let z = zeroGrowthIndex {
      #expect(z > f, "Zero-growth event must follow the first growth event in stream order")
    }

    // MARK: - Phase 2 assertions: model-unload triple

    // Locate the first .modelUnloadStart in the event stream (Phase 2 begins here).
    guard
      let unloadStartIndex = events.firstIndex(where: {
        if case .modelUnloadStart = $0 { return true }
        return false
      })
    else {
      Issue.record("Expected .modelUnloadStart in event stream; none found")
      return
    }

    // The three events must appear consecutively starting at unloadStartIndex:
    //   [unloadStartIndex]   .modelUnloadStart(loaded: false, sizeMB: 0.0)
    //   [unloadStartIndex+1] .modelUnloadComplete(freed: <Double>, processMemoryMB: <Double>)
    //   [unloadStartIndex+2] .metalBufferState(allocatedMB: <Double>, peakMB: -1.0)
    let requiredCount = unloadStartIndex + 3
    #expect(
      events.count >= requiredCount,
      "Expected at least 3 model-lifecycle events starting at index \(unloadStartIndex)")
    guard events.count >= requiredCount else { return }

    // Event 0 of triple: .modelUnloadStart(loaded: false, sizeMB: 0.0)
    if case .modelUnloadStart(let loaded, let sizeMB) = events[unloadStartIndex] {
      #expect(loaded == false, "No model was loaded; unloadModel() is a no-op")
      #expect(sizeMB == 0.0, "estimateModelMemoryUsage() should return 0.0 with no model loaded")
    } else {
      Issue.record(
        "Expected .modelUnloadStart at index \(unloadStartIndex); got \(events[unloadStartIndex])")
    }

    // Event 1 of triple: .modelUnloadComplete (Double fields are runtime-dependent)
    if case .modelUnloadComplete(_, _) = events[unloadStartIndex + 1] {
      // Shape matches. freed and processMemoryMB are runtime values; no value assertion.
    } else {
      Issue.record(
        "Expected .modelUnloadComplete at index \(unloadStartIndex + 1); got \(events[unloadStartIndex + 1])"
      )
    }

    // Event 2 of triple: .metalBufferState(allocatedMB: <Double>, peakMB: -1.0)
    if case .metalBufferState(_, let peakMB) = events[unloadStartIndex + 2] {
      #expect(peakMB == -1.0, "peakMB is always -1.0 — no public MLX peak-counter API")
    } else {
      Issue.record(
        "Expected .metalBufferState at index \(unloadStartIndex + 2); got \(events[unloadStartIndex + 2])"
      )
    }
  }
}
