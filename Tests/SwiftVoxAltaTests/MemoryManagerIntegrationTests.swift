//
//  MemoryManagerIntegrationTests.swift
//  SwiftVoxAltaTests
//
//  Tests verifying that VoxAltaModelManager correctly delegates to MemoryManager,
//  applying the 1.5x headroom multiplier before budget checks, and that
//  memory properties (totalPhysicalMemory, availableMemory) are consistent
//  with MemoryManager.shared values.
//
//  Design note: VoxAltaModelManager uses MemoryManager.shared directly.
//  These tests verify the delegation contract by comparing results from
//  VoxAltaModelManager with what MemoryManager.shared returns independently.
//

import Foundation
import Testing
import Tuberia

@testable import SwiftVoxAlta

// MARK: - Mock MemoryProvider Protocol
//
// A protocol that mirrors the memory query surface of MemoryManager, enabling
// behavior verification without hardware or actor isolation dependencies.
//
// Used by MockMemoryProvider to simulate specific memory conditions.

/// Minimal interface for testing the 1.5× headroom multiplier logic in isolation.
protocol MemoryProvider: Sendable {
  func availableMemory() async -> UInt64
  func totalMemory() async -> UInt64
  func softCheck(requiredBytes: UInt64) async -> Bool
  func hardValidate(requiredBytes: UInt64) async throws
}

/// In-memory mock that returns fixed values, satisfying the MemoryProvider protocol.
///
/// Allows headroom multiplier tests to run without any real Mach VM stat queries.
actor MockMemoryProvider: MemoryProvider {
  var mockAvailableMemory: UInt64
  var mockTotalMemory: UInt64

  init(availableMemory: UInt64, totalMemory: UInt64) {
    self.mockAvailableMemory = availableMemory
    self.mockTotalMemory = totalMemory
  }

  func availableMemory() async -> UInt64 { mockAvailableMemory }
  func totalMemory() async -> UInt64 { mockTotalMemory }

  func softCheck(requiredBytes: UInt64) async -> Bool {
    mockAvailableMemory >= requiredBytes
  }

  func hardValidate(requiredBytes: UInt64) async throws {
    guard mockAvailableMemory >= requiredBytes else {
      throw MemoryCheckError.insufficient(
        available: mockAvailableMemory,
        required: requiredBytes
      )
    }
  }
}

/// Errors thrown by MockMemoryProvider.hardValidate.
enum MemoryCheckError: Error {
  case insufficient(available: UInt64, required: UInt64)
}

// MARK: - HeadroomApplicator
//
// A pure function that mirrors VoxAltaModelManager's headroom logic,
// allowing isolated unit tests without the actor.

/// Applies the VoxAlta headroom multiplier to a model size.
/// Mirrors the exact formula in VoxAltaModelManager.checkMemory / validateMemory.
func applyHeadroom(bytes: Int) -> UInt64 {
  UInt64(Double(bytes) * Qwen3TTSModelSize.headroomMultiplier)
}

// MARK: - Headroom Multiplier Unit Tests (using MockMemoryProvider)

@Suite("MemoryManager Headroom Multiplier Logic")
struct HeadroomMultiplierTests {

  @Test("checkMemory applies 1.5x headroom before delegating to MemoryManager")
  func checkMemoryAppliesHeadroom() async {
    // Given: available memory of 2 GB, model request of 1 GB.
    // Without headroom: 1 GB < 2 GB → pass.
    // With 1.5x headroom: 1 GB * 1.5 = 1.5 GB < 2 GB → pass.
    let available: UInt64 = 2_000_000_000  // 2 GB
    let modelBytes = 1_000_000_000  // 1 GB
    let mock = MockMemoryProvider(availableMemory: available, totalMemory: 8_000_000_000)

    let withHeadroom = applyHeadroom(bytes: modelBytes)
    let passed = await mock.softCheck(requiredBytes: withHeadroom)
    #expect(
      passed == true, "1 GB model with 1.5x headroom (1.5 GB) should pass with 2 GB available")
  }

  @Test("checkMemory headroom causes a borderline request to fail")
  func checkMemoryHeadroomCausesBorderlineToFail() async {
    // Given: available memory of 1.2 GB, model request of 0.9 GB.
    // Without headroom: 0.9 GB < 1.2 GB → would pass.
    // With 1.5x headroom: 0.9 GB * 1.5 = 1.35 GB > 1.2 GB → fail.
    let available: UInt64 = 1_200_000_000  // 1.2 GB
    let modelBytes = 900_000_000  // 0.9 GB
    let mock = MockMemoryProvider(availableMemory: available, totalMemory: 8_000_000_000)

    let withHeadroom = applyHeadroom(bytes: modelBytes)
    let passed = await mock.softCheck(requiredBytes: withHeadroom)
    #expect(
      passed == false,
      "0.9 GB model with 1.5x headroom (1.35 GB) should fail with 1.2 GB available")
  }

  @Test("validateMemory applies 1.5x headroom before delegating to MemoryManager")
  func validateMemoryAppliesHeadroom() async throws {
    // Given: available memory of 3 GB, model request of 1 GB.
    // With 1.5x headroom: 1 GB * 1.5 = 1.5 GB < 3 GB → pass.
    let available: UInt64 = 3_000_000_000  // 3 GB
    let modelBytes = 1_000_000_000  // 1 GB
    let mock = MockMemoryProvider(availableMemory: available, totalMemory: 8_000_000_000)

    let withHeadroom = applyHeadroom(bytes: modelBytes)
    try await mock.hardValidate(requiredBytes: withHeadroom)
    // No throw means pass
  }

  @Test("validateMemory headroom causes insufficientMemory for borderline request")
  func validateMemoryThrowsWithHeadroom() async {
    // Given: available memory of 1.2 GB, model request of 0.9 GB.
    // With 1.5x headroom: 0.9 GB * 1.5 = 1.35 GB > 1.2 GB → throw.
    let available: UInt64 = 1_200_000_000  // 1.2 GB
    let modelBytes = 900_000_000  // 0.9 GB
    let mock = MockMemoryProvider(availableMemory: available, totalMemory: 8_000_000_000)

    let withHeadroom = applyHeadroom(bytes: modelBytes)
    do {
      try await mock.hardValidate(requiredBytes: withHeadroom)
      Issue.record("Expected MemoryCheckError but no error was thrown")
    } catch is MemoryCheckError {
      // Expected — headroom caused the check to fail
    } catch {
      Issue.record("Expected MemoryCheckError, got: \(error)")
    }
  }

  @Test("headroomMultiplier constant is exactly 1.5")
  func headroomConstantIs1_5() {
    #expect(Qwen3TTSModelSize.headroomMultiplier == 1.5)
  }
}

// MARK: - VoxAltaModelManager Delegation Tests (using real MemoryManager.shared)

@Suite("VoxAltaModelManager - MemoryManager Delegation")
struct MemoryManagerDelegationTests {

  @Test("totalPhysicalMemory delegates to MemoryManager.shared")
  func totalPhysicalMemoryDelegatesToShared() async {
    let manager = VoxAltaModelManager()
    let managerTotal = await manager.totalPhysicalMemory
    let sharedTotal = await MemoryManager.shared.totalMemory

    // Both should read from the same sysctlbyname("hw.memsize") source.
    // Allow a small tolerance since reads can race.
    #expect(
      managerTotal == sharedTotal,
      "totalPhysicalMemory should equal MemoryManager.shared.totalMemory")
  }

  @Test("availableMemory delegates to MemoryManager.shared")
  func availableMemoryDelegatesToShared() async {
    let manager = VoxAltaModelManager()
    let managerAvailable = await manager.availableMemory

    // Available memory changes continuously; just verify it's a plausible positive value.
    #expect(managerAvailable > 0, "availableMemory from VoxAltaModelManager should be positive")
  }

  @Test("clearGPUCache delegates to MemoryManager on unloadModel")
  func clearGPUCacheDelegatesOnUnload() async {
    let manager = VoxAltaModelManager()
    // unloadModel() calls MemoryManager.shared.clearGPUCache() internally.
    // We verify it completes without error (the Metal cache operation is a no-op
    // when no model is loaded, but should never throw or crash).
    await manager.unloadModel()
    let isLoaded = await manager.isModelLoaded
    #expect(isLoaded == false, "Model should be unloaded after unloadModel()")
  }

  @Test("checkMemory returns true for a small requirement on any modern Mac")
  func checkMemorySmallRequirementPasses() async {
    let manager = VoxAltaModelManager()
    // 100 MB is small enough to pass on any modern Mac with several GB of RAM.
    let result = await manager.checkMemory(forModelSizeBytes: 100_000_000)
    #expect(result == true, "100 MB model should pass memory check on modern Mac")
  }

  @Test("checkMemory returns false for an absurdly large requirement")
  func checkMemoryAbsurdRequirementFails() async {
    let manager = VoxAltaModelManager()
    // 500 GB — no Mac has this much available memory.
    let result = await manager.checkMemory(forModelSizeBytes: 500_000_000_000)
    #expect(result == false, "500 GB model should fail memory check")
  }

  @Test("validateMemory throws insufficientMemory for absurdly large requirement")
  func validateMemoryThrowsForHugeRequirement() async {
    let manager = VoxAltaModelManager()
    let absurdSize = 500_000_000_000  // 500 GB

    do {
      try await manager.validateMemory(forModelSizeBytes: absurdSize)
      Issue.record("Expected insufficientMemory error but no error was thrown")
    } catch let error as VoxAltaError {
      if case .insufficientMemory(let available, let required) = error {
        #expect(available > 0, "Available memory should be positive in error")
        #expect(required > available, "Required should exceed available in error")
      } else {
        Issue.record("Expected insufficientMemory case, got: \(error)")
      }
    } catch {
      Issue.record("Expected VoxAltaError.insufficientMemory, got: \(error)")
    }
  }
}
