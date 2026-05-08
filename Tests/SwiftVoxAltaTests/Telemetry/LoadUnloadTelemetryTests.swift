//
//  LoadUnloadTelemetryTests.swift
//  SwiftVoxAltaTests
//
//  Sortie 5 — verifies that loadModel and unloadModel emit the correct
//  telemetry events via the capture(_:) helper.
//

import MLX
import MLXAudioCore
import MLXAudioTTS
import MLXLMCommon
import Testing

@testable import SwiftVoxAlta

/// Minimal SpeechGenerationModel that lets tests seed the actor's cache slot
/// without having to load a real ~4 GB model. Methods trap because the
/// cache-hit / no-op-unload tests never call them.
private final class StubSpeechGenerationModel: SpeechGenerationModel, @unchecked Sendable {
  let sampleRate: Int = 24000

  func generate(
    text: String,
    voice: String?,
    refAudio: MLXArray?,
    refText: String?,
    language: String?,
    instruct: String?,
    generationParameters: GenerateParameters
  ) async throws -> MLXArray {
    fatalError("StubSpeechGenerationModel.generate must not be called from tests")
  }

  func generateStream(
    text: String,
    voice: String?,
    refAudio: MLXArray?,
    refText: String?,
    language: String?,
    instruct: String?,
    generationParameters: GenerateParameters
  ) -> AsyncThrowingStream<AudioGeneration, Error> {
    fatalError("StubSpeechGenerationModel.generateStream must not be called from tests")
  }
}

@Suite("VoxAltaModelManager — load/unload telemetry", .acervoEnvironment, .serialized)
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
      try await manager._loadModelDiscardingResult(
        repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    } catch {
      // Expected — we are NOT asserting load success.
    }

    let events = await reporter.events
    // Assert START event was emitted as the first event, regardless of outcome.
    #expect(
      events.first.map { event in
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

  @Test("loadModel cache hit emits NO telemetry (FIX_ME #1)")
  func loadModelCacheHitIsSilent() async {
    let manager = VoxAltaModelManager()
    let reporter = MockTelemetryReporter()
    await manager.setTelemetry(reporter)

    // Seed cache state directly so we can exercise the cache-hit branch
    // without loading a real on-disk model. `_loadModelDiscardingResult`
    // discards the non-Sendable result inside actor isolation.
    let repo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    await manager._setCachedModelForTesting(StubSpeechGenerationModel(), repo: repo)

    do {
      try await manager._loadModelDiscardingResult(repo: repo)
    } catch {
      Issue.record("Cache hit must not throw; got \(error)")
    }

    let events = await reporter.events
    #expect(
      events.isEmpty,
      "Cache hit should emit no telemetry; got \(events.count) event(s): \(events)")
  }

  @Test("loadModel different repo on cache hit unloads + emits real load start")
  func loadModelDifferentRepoTriggersRealLoadTelemetry() async {
    let manager = VoxAltaModelManager()
    let reporter = MockTelemetryReporter()
    await manager.setTelemetry(reporter)

    // Seed with an older repo so the next loadModel takes the unload-then-load
    // path, not the cache-hit short-circuit.
    let oldRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    let newRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    await manager._setCachedModelForTesting(StubSpeechGenerationModel(), repo: oldRepo)

    do {
      try await manager._loadModelDiscardingResult(repo: newRepo)
    } catch {
      // Expected — Acervo has no model on disk in the test sandbox.
    }

    let events = await reporter.events
    let startEvents = events.compactMap { event -> String? in
      if case .modelLoadStart(let repo, let cacheHit) = event {
        return "\(repo)|\(cacheHit)"
      }
      return nil
    }
    // Exactly one modelLoadStart, for the NEW repo, with cacheHit=false.
    #expect(startEvents == ["\(newRepo)|false"])
  }

  @Test("unloadModel restores prior MLX cache limit after draining (FIX_ME #2)")
  func unloadModelRestoresCacheLimit() async {
    let manager = VoxAltaModelManager()

    // Seed a known, distinctive cache limit so we can verify it survives
    // the drain bracket inside unloadModel().
    let sentinel = 7 * 1024 * 1024  // 7 MB — unlikely to coincide with a default
    let originalLimit = Memory.cacheLimit
    Memory.cacheLimit = sentinel
    defer { Memory.cacheLimit = originalLimit }

    await manager.unloadModel()

    #expect(
      Memory.cacheLimit == sentinel,
      "unloadModel must restore the prior cacheLimit; got \(Memory.cacheLimit), expected \(sentinel)"
    )
  }

  @Test("Telemetry nil reporter is a no-op (no crash on load/unload without reporter)")
  func nilTelemetryIsNoOp() async {
    let manager = VoxAltaModelManager()
    // No setTelemetry call — telemetry is nil.

    do {
      // Use _loadModelDiscardingResult to avoid the non-Sendable return type
      // of any SpeechGenerationModel crossing actor isolation.
      try await manager._loadModelDiscardingResult(
        repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    } catch {
      // Expected.
    }
    await manager.unloadModel()
    // Reaching this point without trapping is the assertion.
    #expect(Bool(true))
  }
}
