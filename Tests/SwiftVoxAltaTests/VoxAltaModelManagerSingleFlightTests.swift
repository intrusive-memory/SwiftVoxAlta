//
//  VoxAltaModelManagerSingleFlightTests.swift
//  SwiftVoxAltaTests
//
//  Regression test for the single-flight `loadModel` coalescing guard.
//
//  Background: `VoxAltaModelManager` is a Swift actor, but actors are
//  reentrant across `await` points. Without an explicit single-flight
//  guard, N concurrent callers can each pass the cache check before any
//  one finishes loading, then each independently mmap a multi-GB model.
//  Observed in practice: 24 concurrent envelope-driven calls × ~4 GB =
//  ~96 GB virtual footprint before macOS reclaim killed the process.
//

import Foundation
import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaModelManager — Single-flight loadModel", .acervoEnvironment)
struct VoxAltaModelManagerSingleFlightTests {

  /// Concurrent `loadModel` calls for the same repo must coalesce onto a
  /// single underlying load. We use a repo string that isn't a recognised
  /// `Qwen3TTSModelRepo` so the load throws fast (no model files touched);
  /// the assertion is on `performLoadInvocationCount`, which must stay at 1.
  @Test("Concurrent loadModel calls coalesce onto one underlying load")
  func concurrentLoadsCoalesce() async throws {
    let manager = VoxAltaModelManager()
    let unknownRepo = "test-only-unknown-repo-not-a-real-Qwen3TTSModelRepo"

    let concurrency = 16
    let results: [Result<Void, any Error>] = await withTaskGroup(
      of: Result<Void, any Error>.self
    ) { group in
      for _ in 0..<concurrency {
        group.addTask {
          do {
            try await manager._loadModelDiscardingResult(repo: unknownRepo)
            return .success(())
          } catch {
            return .failure(error)
          }
        }
      }
      var collected: [Result<Void, any Error>] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // Every concurrent caller must receive the load's error — none should
    // hang and none should silently succeed against an unknown repo.
    #expect(results.count == concurrency)
    let failures = results.compactMap { result -> (any Error)? in
      if case .failure(let error) = result { return error }
      return nil
    }
    #expect(failures.count == concurrency, "All concurrent calls should fail with the same error")
    for error in failures {
      guard let voxError = error as? VoxAltaError else {
        Issue.record("Expected VoxAltaError, got \(type(of: error))")
        continue
      }
      if case .modelNotAvailable = voxError {
        // Expected
      } else {
        Issue.record("Expected modelNotAvailable, got \(voxError)")
      }
    }

    // The core regression assertion: only one underlying load ran.
    let invocations = await manager.performLoadInvocationCount
    #expect(
      invocations == 1,
      "Expected single-flight: 1 _performLoad invocation for \(concurrency) concurrent calls, got \(invocations)"
    )
  }

  /// After a failed load completes and clears `inFlightLoad`, a subsequent
  /// call must be free to start a fresh load. This guards against the fix
  /// over-coalescing across distinct retry boundaries.
  @Test("Failed load clears in-flight state so next call retries")
  func failedLoadClearsState() async throws {
    let manager = VoxAltaModelManager()
    let unknownRepo = "test-only-unknown-repo-not-a-real-Qwen3TTSModelRepo"

    // First call: fails.
    do {
      try await manager._loadModelDiscardingResult(repo: unknownRepo)
      Issue.record("Expected first call to throw")
    } catch {
      // Expected
    }

    let firstCount = await manager.performLoadInvocationCount
    #expect(firstCount == 1)

    // Second call (sequential, after first fully returned): must run a
    // fresh load — not see a stale in-flight task or a stale cache hit.
    do {
      try await manager._loadModelDiscardingResult(repo: unknownRepo)
      Issue.record("Expected second call to throw")
    } catch {
      // Expected
    }

    let secondCount = await manager.performLoadInvocationCount
    #expect(
      secondCount == 2,
      "Sequential failed loads should each invoke _performLoad; got \(secondCount)"
    )
  }
}
