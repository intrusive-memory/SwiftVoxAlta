//
//  ConsistencyTests.swift
//  SwiftVoxAltaTests
//
//  Voice consistency validation tests: round-trip serialization, audio conversion
//  fidelity, voice description determinism, and parenthetical mapping consistency.
//

import Foundation
import Testing
@preconcurrency import MLX
@testable import SwiftVoxAlta

// MARK: - VoiceLock Round-Trip Tests

@Suite("Consistency - VoiceLock Round-Trip")
struct VoiceLockRoundTripTests {

    @Test("VoiceLock round-trips through JSON: all fields match")
    func voiceLockJSONRoundTrip() throws {
        let cloneData = Data((0..<1024).map { UInt8($0 % 256) })
        let lockDate = Date(timeIntervalSince1970: 1_700_000_000)

        let original = VoiceLock(
            characterName: "ELENA",
            clonePromptData: cloneData,
            designInstruction: "A warm female voice in her 30s with slightly husky quality.",
            lockedAt: lockDate
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == original.characterName)
        #expect(decoded.clonePromptData == original.clonePromptData)
        #expect(decoded.designInstruction == original.designInstruction)
        #expect(decoded.lockedAt == original.lockedAt)
    }

    @Test("VoiceLock round-trips through PropertyList: all fields match")
    func voiceLockPlistRoundTrip() throws {
        let cloneData = Data((0..<512).map { UInt8($0 % 256) })
        let lockDate = Date()

        let original = VoiceLock(
            characterName: "MARCUS",
            clonePromptData: cloneData,
            designInstruction: "A deep male voice, 40s, measured and calm.",
            lockedAt: lockDate
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == original.characterName)
        #expect(decoded.clonePromptData == original.clonePromptData)
        #expect(decoded.designInstruction == original.designInstruction)
        // Date comparison: PropertyList may lose sub-millisecond precision
        #expect(abs(decoded.lockedAt.timeIntervalSince(original.lockedAt)) < 0.001)
    }

    @Test("VoiceLock preserves large clone prompt data integrity")
    func voiceLockLargeCloneData() throws {
        // Simulate a realistic clone prompt (16 KB)
        let largeData = Data((0..<16384).map { UInt8($0 % 256) })

        let original = VoiceLock(
            characterName: "NARRATOR",
            clonePromptData: largeData,
            designInstruction: "Omniscient narrator voice."
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.clonePromptData.count == 16384)
        #expect(decoded.clonePromptData == largeData,
                "Large clone prompt data should be perfectly preserved through serialization")
    }

    @Test("VoiceLock with empty clone data round-trips")
    func voiceLockEmptyCloneData() throws {
        let original = VoiceLock(
            characterName: "PHANTOM",
            clonePromptData: Data(),
            designInstruction: ""
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == "PHANTOM")
        #expect(decoded.clonePromptData.isEmpty)
        #expect(decoded.designInstruction.isEmpty)
    }
}

// MARK: - AudioConversion Round-Trip Tests

@Suite("Consistency - AudioConversion Round-Trip")
struct AudioConversionRoundTripTests {

    @Test("MLXArray to WAV to MLXArray preserves sample values within quantization error")
    func audioRoundTripPreservesValues() throws {
        let originalSamples: [Float] = [0.0, 0.1, -0.1, 0.5, -0.5, 0.9, -0.9]
        let original = MLXArray(originalSamples)

        let wavData = try AudioConversion.mlxArrayToWAVData(original)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let restoredSamples = restored.asArray(Float.self)

        // 16-bit quantization error is at most 1/32767
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6

        #expect(restoredSamples.count == originalSamples.count,
                "Sample count should be preserved")

        for (i, orig) in originalSamples.enumerated() {
            let diff = abs(restoredSamples[i] - orig)
            #expect(diff < maxError,
                    "Sample \(i): expected ~\(orig), got \(restoredSamples[i]), diff=\(diff)")
        }
    }

    @Test("Round-trip preserves sample count for various lengths")
    func audioRoundTripPreservesCount() throws {
        for count in [1, 10, 100, 1000, 24000] {
            let samples = (0..<count).map { Float(sin(Double($0) * 0.01)) }
            let original = MLXArray(samples)

            let wavData = try AudioConversion.mlxArrayToWAVData(original, sampleRate: 24000)
            let restored = try AudioConversion.wavDataToMLXArray(wavData)

            #expect(restored.size == count,
                    "Round-trip should preserve \(count) samples, got \(restored.size)")
        }
    }

    @Test("Double round-trip maintains fidelity within quantization")
    func doubleRoundTripMaintainsFidelity() throws {
        let originalSamples: [Float] = [0.3, -0.7, 0.0, 0.99, -0.99]
        let original = MLXArray(originalSamples)

        // First round-trip
        let wav1 = try AudioConversion.mlxArrayToWAVData(original)
        let restored1 = try AudioConversion.wavDataToMLXArray(wav1)

        // Second round-trip
        let wav2 = try AudioConversion.mlxArrayToWAVData(restored1)
        let restored2 = try AudioConversion.wavDataToMLXArray(wav2)

        let samples1 = restored1.asArray(Float.self)
        let samples2 = restored2.asArray(Float.self)

        // After the first quantization, subsequent round-trips should be lossless
        // because the values are already quantized to 16-bit grid
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6
        for i in 0..<samples1.count {
            let diff = abs(samples1[i] - samples2[i])
            #expect(diff < maxError,
                    "Double round-trip sample \(i): first=\(samples1[i]), second=\(samples2[i])")
        }
    }

    @Test("Round-trip of sine wave preserves waveform shape")
    func sineWaveRoundTrip() throws {
        let sampleRate = 24000
        let frequency: Float = 440.0
        let duration = 0.1  // 100ms
        let sampleCount = Int(Double(sampleRate) * duration)

        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = 0.8 * sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
        }

        let original = MLXArray(samples)
        let wavData = try AudioConversion.mlxArrayToWAVData(original, sampleRate: sampleRate)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let restoredSamples = restored.asArray(Float.self)
        #expect(restoredSamples.count == sampleCount)

        // Check that the waveform shape is preserved (correlation)
        var dotProduct: Float = 0
        var origNorm: Float = 0
        var restNorm: Float = 0
        for i in 0..<sampleCount {
            dotProduct += samples[i] * restoredSamples[i]
            origNorm += samples[i] * samples[i]
            restNorm += restoredSamples[i] * restoredSamples[i]
        }

        let correlation = dotProduct / (sqrt(origNorm) * sqrt(restNorm) + 1e-10)
        #expect(correlation > 0.999,
                "Sine wave correlation should be very high, got \(correlation)")
    }
}

