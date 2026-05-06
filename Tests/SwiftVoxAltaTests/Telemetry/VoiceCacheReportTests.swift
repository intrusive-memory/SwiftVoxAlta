//
//  VoiceCacheReportTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 6 — verifies VoxAltaVoiceCache.reportState() and the provider's
//  voiceCacheGrowth emissions from loadVoice, unloadVoice, and unloadAllVoices.
//

import Foundation
import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaVoiceCache — reportState + growth events", .acervoEnvironment)
struct VoiceCacheReportTests {

  @Test("reportState reflects inserted data accurately")
  func reportStateMatchesInsertedData() async {
    let cache = VoxAltaVoiceCache()
    // gender: is String? in this codebase, not a typed enum.
    await cache.store(id: "A", data: Data(repeating: 0, count: 100), gender: "female")
    await cache.store(id: "B", data: Data(repeating: 0, count: 200), gender: "female")
    await cache.store(id: "C", data: Data(repeating: 0, count: 300), gender: "female")

    let state = await cache.reportState()
    #expect(state.entriesCount == 3)
    #expect(state.totalBytesCached == 600)
    #expect(state.topVoicesBySize.first?.bytes == 300)
  }

  @Test("topVoicesBySize is capped at 5 entries")
  func topVoicesBySizeLimit() async {
    let cache = VoxAltaVoiceCache()
    for i in 0..<7 {
      await cache.store(
        id: "voice-\(i)",
        data: Data(repeating: 0, count: 100 * (i + 1)),
        gender: "female"
      )
    }
    let state = await cache.reportState()
    #expect(state.topVoicesBySize.count == 5)
  }

  @Test("Provider emits voiceCacheGrowth after loadVoice")
  func providerEmitsGrowthOnLoadVoice() async {
    let provider = VoxAltaVoiceProvider()
    let reporter = MockTelemetryReporter()
    await provider.setTelemetry(reporter)

    await provider.loadVoice(id: "TEST", clonePromptData: Data(repeating: 0, count: 1024))

    let events = await reporter.events
    let hasGrowth = events.contains { event in
      if case .voiceCacheGrowth(let entriesCount, _) = event {
        return entriesCount == 1
      }
      return false
    }
    #expect(hasGrowth)
  }

  @Test("Provider emits voiceCacheGrowth(entriesCount: 0) after unloadVoice")
  func providerEmitsGrowthOnUnload() async {
    let provider = VoxAltaVoiceProvider()
    let reporter = MockTelemetryReporter()
    await provider.setTelemetry(reporter)

    await provider.loadVoice(id: "TEST", clonePromptData: Data(repeating: 0, count: 1024))
    await provider.unloadVoice(id: "TEST")

    let events = await reporter.events
    let hasZeroGrowth = events.contains { event in
      if case .voiceCacheGrowth(let entriesCount, let totalMB) = event {
        return entriesCount == 0 && totalMB == 0.0
      }
      return false
    }
    #expect(hasZeroGrowth)
  }
}
