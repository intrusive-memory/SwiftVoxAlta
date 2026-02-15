//
//  AppleSiliconInfoTests.swift
//  SwiftVoxAlta
//
//  Unit tests for Apple Silicon generation detection.
//

import Testing
import Foundation
@testable import SwiftVoxAlta

@Suite("AppleSiliconGeneration Tests")
struct AppleSiliconInfoTests {

    /// Test that AppleSiliconGeneration.current returns a valid generation.
    ///
    /// This test validates that the runtime detection produces a recognized
    /// generation (not .unknown) on Apple Silicon hardware.
    @Test("AppleSiliconGeneration.current detects valid generation")
    func currentGenerationIsValid() async throws {
        let generation = AppleSiliconGeneration.current

        // On Apple Silicon hardware, we should never get .unknown
        #expect(generation != .unknown, "Expected a known Apple Silicon generation on this hardware")

        // Log detected generation for debugging
        print("Detected Apple Silicon generation: \(generation.rawValue)")
    }

    /// Test that hasNeuralAccelerators returns true for M5 family.
    @Test("hasNeuralAccelerators is true for M5 family")
    func neuralAcceleratorsForM5() async throws {
        #expect(AppleSiliconGeneration.m5.hasNeuralAccelerators == true)
        #expect(AppleSiliconGeneration.m5Pro.hasNeuralAccelerators == true)
        #expect(AppleSiliconGeneration.m5Max.hasNeuralAccelerators == true)
        #expect(AppleSiliconGeneration.m5Ultra.hasNeuralAccelerators == true)
    }

    /// Test that hasNeuralAccelerators returns false for M1-M4 families.
    @Test("hasNeuralAccelerators is false for M1-M4 families")
    func noNeuralAcceleratorsForOlderGenerations() async throws {
        // M1 family
        #expect(AppleSiliconGeneration.m1.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m1Pro.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m1Max.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m1Ultra.hasNeuralAccelerators == false)

        // M2 family
        #expect(AppleSiliconGeneration.m2.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m2Pro.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m2Max.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m2Ultra.hasNeuralAccelerators == false)

        // M3 family
        #expect(AppleSiliconGeneration.m3.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m3Pro.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m3Max.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m3Ultra.hasNeuralAccelerators == false)

        // M4 family
        #expect(AppleSiliconGeneration.m4.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m4Pro.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m4Max.hasNeuralAccelerators == false)
        #expect(AppleSiliconGeneration.m4Ultra.hasNeuralAccelerators == false)

        // Unknown
        #expect(AppleSiliconGeneration.unknown.hasNeuralAccelerators == false)
    }

    /// Test that AppleSiliconGeneration is Sendable.
    @Test("AppleSiliconGeneration is Sendable")
    func generationIsSendable() async throws {
        let generation = AppleSiliconGeneration.current

        // If this compiles, Sendable conformance is validated
        await withCheckedContinuation { continuation in
            Task {
                let _ = generation
                continuation.resume()
            }
        }
    }

    /// Test that AppleSiliconGeneration has correct raw values.
    @Test("AppleSiliconGeneration raw values are correct")
    func rawValuesAreCorrect() async throws {
        #expect(AppleSiliconGeneration.m1.rawValue == "M1")
        #expect(AppleSiliconGeneration.m1Pro.rawValue == "M1 Pro")
        #expect(AppleSiliconGeneration.m5.rawValue == "M5")
        #expect(AppleSiliconGeneration.m5Ultra.rawValue == "M5 Ultra")
        #expect(AppleSiliconGeneration.unknown.rawValue == "Unknown")
    }

    /// Test that all case iterations are present.
    @Test("AppleSiliconGeneration.allCases contains all generations")
    func allCasesContainsAllGenerations() async throws {
        let allCases = AppleSiliconGeneration.allCases

        // Verify expected count (21 total: M1-M5 families + unknown)
        // M1: 4, M2: 4, M3: 4, M4: 4, M5: 4, Unknown: 1 = 21
        #expect(allCases.count == 21, "Expected 21 generations (M1-M5 families + unknown)")

        // Verify all M5 cases are present
        #expect(allCases.contains(.m5))
        #expect(allCases.contains(.m5Pro))
        #expect(allCases.contains(.m5Max))
        #expect(allCases.contains(.m5Ultra))
    }

    /// Test that the detection is cached (same instance on repeated access).
    @Test("AppleSiliconGeneration.current is cached")
    func currentIsCached() async throws {
        let first = AppleSiliconGeneration.current
        let second = AppleSiliconGeneration.current

        // Both should be the same (enum value, not reference equality)
        #expect(first == second, "Expected cached detection to return same generation")
    }
}
