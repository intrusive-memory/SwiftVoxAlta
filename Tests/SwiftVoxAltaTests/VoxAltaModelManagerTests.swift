//
//  VoxAltaModelManagerTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoxAltaModelManager actor: model lifecycle, caching,
//  memory validation, and type conformance.
//

import Testing
import Foundation
import SwiftAcervo
@testable import SwiftVoxAlta

// MARK: - Actor Conformance Tests

@Suite("VoxAltaModelManager - Actor & Sendable Conformance")
struct ModelManagerConformanceTests {

    @Test("VoxAltaModelManager is an actor and conforms to Sendable")
    func actorIsSendable() async {
        // Creating an instance and passing it across isolation boundaries
        // exercises the Sendable conformance. If this compiles, the actor
        // is Sendable (all actors are implicitly Sendable in Swift).
        let manager = VoxAltaModelManager()
        let isSendable: any Sendable = manager
        #expect(isSendable is VoxAltaModelManager)
    }

    @Test("VoxAltaModelManager can be shared across tasks")
    func actorSharedAcrossTasks() async {
        let manager = VoxAltaModelManager()

        // Access from multiple concurrent tasks to verify actor isolation works
        async let loaded1 = manager.isModelLoaded
        async let loaded2 = manager.isModelLoaded
        async let repo1 = manager.currentModelRepo

        let results = await (loaded1, loaded2, repo1)
        #expect(results.0 == false)
        #expect(results.1 == false)
        #expect(results.2 == nil)
    }
}

// MARK: - Initial State Tests

@Suite("VoxAltaModelManager - Initial State")
struct ModelManagerInitialStateTests {

    @Test("isModelLoaded is false initially")
    func initiallyNotLoaded() async {
        let manager = VoxAltaModelManager()
        let loaded = await manager.isModelLoaded
        #expect(loaded == false)
    }

    @Test("currentModelRepo is nil initially")
    func initiallyNoRepo() async {
        let manager = VoxAltaModelManager()
        let repo = await manager.currentModelRepo
        #expect(repo == nil)
    }

    @Test("unloadModel is safe to call when no model is loaded")
    func unloadWhenEmpty() async {
        let manager = VoxAltaModelManager()
        await manager.unloadModel()
        let loaded = await manager.isModelLoaded
        #expect(loaded == false)
    }
}

// MARK: - Memory Check (Non-Throwing) Tests

@Suite("VoxAltaModelManager - Memory Check (Non-Throwing)")
struct MemoryCheckTests {

    @Test("checkMemory returns true for small requirement")
    func checkSmallReturnsTrue() async {
        let manager = VoxAltaModelManager()
        let ok = await manager.checkMemory(forModelSizeBytes: 100_000_000)
        #expect(ok == true)
    }

    @Test("checkMemory returns false for absurdly large requirement without throwing")
    func checkHugeReturnsFalse() async {
        let manager = VoxAltaModelManager()
        // 500 GB — should return false, not throw
        let ok = await manager.checkMemory(forModelSizeBytes: 500_000_000_000)
        #expect(ok == false)
    }
}

// MARK: - Memory Validation Tests (Legacy Throwing)

@Suite("VoxAltaModelManager - Memory Validation")
struct MemoryValidationTests {

    @Test("validateMemory passes for small model requirements on modern Mac")
    func validateSmallModelPasses() async throws {
        let manager = VoxAltaModelManager()

        // 100 MB should pass on any modern Mac with several GB of RAM
        try await manager.validateMemory(forModelSizeBytes: 100_000_000)
    }

    @Test("validateMemory passes for realistic 0.6B model size")
    func validateRealistic0_6BPasses() async throws {
        let manager = VoxAltaModelManager()
        let availableMemory = await manager.availableMemory

        // Only run this test if the machine currently has enough free RAM
        // (0.6B bf16 needs ~1.2GB * 1.5 = ~1.8GB)
        let requiredSize = Qwen3TTSModelSize.knownSizes[
            Qwen3TTSModelRepo.base0_6B.rawValue
        ]!
        let headroomNeeded = Int(Double(requiredSize) * Qwen3TTSModelSize.headroomMultiplier)

        if availableMemory > UInt64(headroomNeeded) {
            try await manager.validateMemory(forModelSizeBytes: requiredSize)
        }
        // If available memory is less than needed (system under load), skip gracefully
    }

    @Test("validateMemory throws insufficientMemory for unrealistically large requirement")
    func validateThrowsForHugeModel() async {
        let manager = VoxAltaModelManager()

        // Request 500 GB -- no current Mac has this much available memory
        let absurdSize = 500_000_000_000

        do {
            try await manager.validateMemory(forModelSizeBytes: absurdSize)
            Issue.record("Expected insufficientMemory error but validation passed")
        } catch let error as VoxAltaError {
            // Verify it's the right error case
            if case .insufficientMemory(let available, let required) = error {
                #expect(available > 0, "Available memory should be reported as positive")
                #expect(required > available, "Required memory should exceed available")
            } else {
                Issue.record("Expected insufficientMemory, got: \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError.insufficientMemory, got: \(error)")
        }
    }

    @Test("validateMemory applies 1.5x headroom multiplier")
    func validateHeadroomMultiplier() async {
        let manager = VoxAltaModelManager()
        let available = await manager.availableMemory

        // Request a size that is less than available but more than available/1.5
        // This should fail because the headroom pushes the requirement above available.
        let sizeJustOverThreshold = Int(Double(available) * 0.8)  // 80% of available

        // With 1.5x headroom: 0.8 * 1.5 = 1.2 of available -- should fail
        do {
            try await manager.validateMemory(forModelSizeBytes: sizeJustOverThreshold)
            Issue.record("Expected insufficientMemory for size requiring 1.2x available memory")
        } catch is VoxAltaError {
            // Expected: 0.8 * available * 1.5 = 1.2 * available > available
        } catch {
            Issue.record("Expected VoxAltaError, got: \(error)")
        }

        // Request a size that with headroom is still under available
        let sizeSafelyUnder = Int(Double(available) * 0.5)  // 50% of available

        // With 1.5x headroom: 0.5 * 1.5 = 0.75 of available -- should pass
        do {
            try await manager.validateMemory(forModelSizeBytes: sizeSafelyUnder)
        } catch {
            Issue.record("Expected validation to pass for size requiring 0.75x available, got: \(error)")
        }
    }

    @Test("totalPhysicalMemory reports a reasonable value")
    func totalPhysicalMemoryIsReasonable() async {
        let manager = VoxAltaModelManager()
        let total = await manager.totalPhysicalMemory

        // Any Mac running this should have at least 4GB
        #expect(total >= 4_000_000_000, "Expected at least 4GB physical memory")
        // And less than 1 TB
        #expect(total < 1_000_000_000_000, "Expected less than 1TB physical memory")
    }

    @Test("availableMemory reports a positive value")
    func availableMemoryIsPositive() async {
        let manager = VoxAltaModelManager()
        let available = await manager.availableMemory

        #expect(available > 0, "Available memory should be positive")
    }
}

// MARK: - Model Repo Enum Tests

@Suite("Qwen3TTSModelRepo - Model Repository Identifiers")
struct ModelRepoTests {

    @Test("All model repo raw values are valid HuggingFace repo identifiers")
    func repoRawValuesAreValid() {
        for repo in Qwen3TTSModelRepo.allCases {
            let raw = repo.rawValue
            #expect(raw.contains("/"), "Repo '\(raw)' should contain '/' separator")
            let parts = raw.split(separator: "/")
            #expect(parts.count == 2, "Repo '\(raw)' should have exactly 2 parts: org/model")
            #expect(parts[0] == "mlx-community", "Repo '\(raw)' should be in mlx-community org")
        }
    }

    @Test("All model repos have display names")
    func reposHaveDisplayNames() {
        for repo in Qwen3TTSModelRepo.allCases {
            #expect(!repo.displayName.isEmpty, "Repo \(repo) should have a non-empty display name")
        }
    }

    @Test("All model repos have known size estimates")
    func reposHaveKnownSizes() {
        for repo in Qwen3TTSModelRepo.allCases {
            let size = Qwen3TTSModelSize.knownSizes[repo.rawValue]
            #expect(size != nil, "Repo \(repo.rawValue) should have a known size estimate")
            if let size {
                #expect(size > 0, "Size for \(repo.rawValue) should be positive")
            }
        }
    }
}

// MARK: - Model Size Constants Tests

@Suite("Qwen3TTSModelSize - Size Estimates")
struct ModelSizeTests {

    @Test("1.7B bf16 models are larger than 0.6B bf16 models")
    func largeModelsAreLarger() {
        let voiceDesign1_7B = Qwen3TTSModelSize.knownSizes[
            Qwen3TTSModelRepo.voiceDesign1_7B.rawValue
        ]!
        let base1_7B = Qwen3TTSModelSize.knownSizes[
            Qwen3TTSModelRepo.base1_7B.rawValue
        ]!
        let base0_6B = Qwen3TTSModelSize.knownSizes[
            Qwen3TTSModelRepo.base0_6B.rawValue
        ]!

        #expect(voiceDesign1_7B > base0_6B)
        #expect(base1_7B > base0_6B)
    }

    @Test("Quantized models are smaller than bf16 counterparts")
    func quantizedModelsAreSmaller() {
        let bf16 = Qwen3TTSModelSize.knownSizes[
            "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
        ]!
        let eightBit = Qwen3TTSModelSize.knownSizes[
            "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
        ]!
        let fourBit = Qwen3TTSModelSize.knownSizes[
            "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit"
        ]!

        #expect(bf16 > eightBit, "bf16 should be larger than 8-bit quantized")
        #expect(eightBit > fourBit, "8-bit should be larger than 4-bit quantized")
    }

    @Test("Headroom multiplier is 1.5")
    func headroomIs1_5() {
        #expect(Qwen3TTSModelSize.headroomMultiplier == 1.5)
    }
}

// MARK: - VoxAltaError Tests (insufficientMemory)

@Suite("VoxAltaError - Insufficient Memory")
struct InsufficientMemoryErrorTests {

    @Test("insufficientMemory error has descriptive message")
    func errorHasDescription() {
        let error = VoxAltaError.insufficientMemory(
            available: 2_000_000_000,
            required: 5_000_000_000
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("2000000000"), "Description should contain available bytes")
        #expect(description.contains("5000000000"), "Description should contain required bytes")
    }

    @Test("insufficientMemory error is Sendable")
    func errorIsSendable() {
        let error: any Sendable = VoxAltaError.insufficientMemory(
            available: 1_000_000_000,
            required: 2_000_000_000
        )
        #expect(error is VoxAltaError)
    }
}

// MARK: - Acervo Integration Tests

@Suite("VoxAltaModelManager - Acervo Integration")
struct AcervoIntegrationTests {

    @Test("isModelInAcervo returns false for non-existent model")
    func isModelInAcervoMissing() async {
        let manager = VoxAltaModelManager()
        let result = await manager.isModelInAcervo("test-org/nonexistent-\(UUID().uuidString)")
        #expect(result == false)
    }

    @Test("isModelInAcervo returns true when model exists in Acervo directory")
    func isModelInAcervoPresent() async throws {
        let tempModelId = "test-org/voxalta-acervo-test-\(UUID().uuidString)"
        let modelDir = try Acervo.modelDirectory(for: tempModelId)
        defer { try? FileManager.default.removeItem(at: modelDir) }

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDir.appendingPathComponent("config.json"))

        let manager = VoxAltaModelManager()
        let result = await manager.isModelInAcervo(tempModelId)
        #expect(result == true)
    }

    @Test("migrateIfNeeded runs without error on clean system")
    func migrateIfNeededRuns() async {
        let manager = VoxAltaModelManager()
        await manager.migrateIfNeeded()
        // Should not throw; migration is a no-op if legacy path is empty
    }

    @Test("migrateIfNeeded only runs once per session")
    func migrateIfNeededIdempotent() async {
        let manager = VoxAltaModelManager()
        await manager.migrateIfNeeded()
        await manager.migrateIfNeeded()
        // Second call should be a no-op (migrationAttempted flag)
    }

    @Test("Acervo shared models directory is ~/Library/SharedModels/")
    func sharedModelsDirectory() {
        let dir = Acervo.sharedModelsDirectory
        #expect(dir.path.hasSuffix("Library/SharedModels"))
    }
}
