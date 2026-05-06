//
//  LoadUnloadTelemetryTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 5 — verifies that loadModel and unloadModel emit the correct
//  telemetry events via the capture(_:) helper.
//

import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaModelManager — load/unload telemetry", .acervoEnvironment)
struct LoadUnloadTelemetryTests {

  @Test("loadModel emits .modelLoadStart even when load throws")
  func loadModelEmitsStartEvenOnThrow() async {
    let manager = VoxAltaModelManager()
    let reporter = MockTelemetryReporter()
    await manager.setTelemetry(reporter)

    do {
      // The load may throw if Acervo can't write to the model cache directory
      // (xcodebuild sandbox) or if the model isn't on disk. Expected.
      // Use _loadModelDiscardingResult to avoid the non-Sendable return type
      // of any SpeechGenerationModel crossing actor isolation.
      try await manager._loadModelDiscardingResult(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    } catch {
      // Expected — we are NOT asserting load success.
    }

    let events = await reporter.events
    // Assert START event was emitted as the first event, regardless of outcome.
    #expect(events.first.map { event in
      if case .modelLoadStart(let repo, let cacheHit) = event {
        return repo == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16" && cacheHit == false
      }
      return false
    } ?? false)
  }

  @Test("unloadModel emits start + complete even when no model is loaded")
  func unloadModelEmitsStartAndCompleteOnNoOp() async {
    let manager = VoxAltaModelManager()
    let reporter = MockTelemetryReporter()
    await manager.setTelemetry(reporter)

    await manager.unloadModel()

    let events = await reporter.events
    // Sortie 7 adds a .metalBufferState event immediately after .modelUnloadComplete,
    // so the no-op unload now produces 3 events: start, complete, metalBufferState.
    #expect(events.count == 3)

    // Match shape of first event without comparing Double fields with raw equality.
    if events.count >= 1 {
      if case .modelUnloadStart(let loaded, let sizeMB) = events[0] {
        #expect(loaded == false)
        #expect(sizeMB == 0.0)
      } else {
        Issue.record("Expected .modelUnloadStart as first event; got \(events[0])")
      }
    }

    // Second event: shape only — Double values are runtime-dependent.
    if events.count >= 2 {
      if case .modelUnloadComplete(_, _) = events[1] {
        // shape matches
      } else {
        Issue.record("Expected .modelUnloadComplete as second event; got \(events[1])")
      }
    }

    // Third event: .metalBufferState emitted after unloadComplete (Sortie 7).
    if events.count >= 3 {
      if case .metalBufferState(_, let peakMB) = events[2] {
        #expect(peakMB == -1.0)
      } else {
        Issue.record("Expected .metalBufferState as third event; got \(events[2])")
      }
    }
  }

  @Test("Telemetry nil reporter is a no-op (no crash on load/unload without reporter)")
  func nilTelemetryIsNoOp() async {
    let manager = VoxAltaModelManager()
    // No setTelemetry call — telemetry is nil.

    do {
      // Use _loadModelDiscardingResult to avoid the non-Sendable return type
      // of any SpeechGenerationModel crossing actor isolation.
      try await manager._loadModelDiscardingResult(repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    } catch {
      // Expected.
    }
    await manager.unloadModel()
    // Reaching this point without trapping is the assertion.
    #expect(Bool(true))
  }
}
