//
//  AudioConversionTests.swift
//  SwiftVoxAltaTests
//
//  Tests for AudioConversion WAV ↔ MLXArray conversion utilities.
//

import Foundation
import Testing
@preconcurrency import MLX
@testable import SwiftVoxAlta

@Suite("AudioConversion - WAV Header Generation")
struct WAVHeaderTests {

    @Test("Generated WAV data starts with RIFF header")
    func wavStartsWithRIFF() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let riff = String(data: wavData[0..<4], encoding: .ascii)
        #expect(riff == "RIFF")
    }

    @Test("Generated WAV data contains WAVE format marker")
    func wavContainsWAVEMarker() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let wave = String(data: wavData[8..<12], encoding: .ascii)
        #expect(wave == "WAVE")
    }

    @Test("Generated WAV data contains fmt chunk")
    func wavContainsFmtChunk() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let fmt = String(data: wavData[12..<16], encoding: .ascii)
        #expect(fmt == "fmt ")
    }

    @Test("Generated WAV data contains data chunk")
    func wavContainsDataChunk() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let dataMarker = String(data: wavData[36..<40], encoding: .ascii)
        #expect(dataMarker == "data")
    }

    @Test("WAV header encodes 24kHz sample rate")
    func wavEncodes24kHzSampleRate() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples, sampleRate: 24000)

        let sampleRate = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 24, as: UInt32.self).littleEndian
        }
        #expect(sampleRate == 24000)
    }

    @Test("WAV header encodes mono channel count")
    func wavEncodesMonoChannels() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let channels = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 22, as: UInt16.self).littleEndian
        }
        #expect(channels == 1)
    }

    @Test("WAV header encodes 16-bit sample depth")
    func wavEncodes16BitDepth() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let bitsPerSample = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 34, as: UInt16.self).littleEndian
        }
        #expect(bitsPerSample == 16)
    }

    @Test("WAV header encodes PCM format tag")
    func wavEncodesPCMFormat() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 100))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let formatTag = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 20, as: UInt16.self).littleEndian
        }
        #expect(formatTag == 1, "Format tag should be 1 (PCM)")
    }

    @Test("WAV file size field is correct")
    func wavFileSizeIsCorrect() throws {
        let sampleCount = 100
        let samples = MLXArray([Float](repeating: 0.0, count: sampleCount))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let fileSize = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        // File size = total - 8 (RIFF + size field) = 44 header + data - 8
        let expectedFileSize = UInt32(36 + sampleCount * 2)
        #expect(fileSize == expectedFileSize)
    }

    @Test("WAV data chunk size matches sample count")
    func wavDataChunkSizeMatchesSamples() throws {
        let sampleCount = 256
        let samples = MLXArray([Float](repeating: 0.5, count: sampleCount))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples)

        let dataSize = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataSize == UInt32(sampleCount * 2), "Data size should be sampleCount * 2 bytes (16-bit)")
    }

    @Test("WAV with custom sample rate encodes correctly")
    func wavCustomSampleRate() throws {
        let samples = MLXArray([Float](repeating: 0.0, count: 10))
        let wavData = try AudioConversion.mlxArrayToWAVData(samples, sampleRate: 44100)

        let sampleRate = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 24, as: UInt32.self).littleEndian
        }
        #expect(sampleRate == 44100)
    }
}

@Suite("AudioConversion - Round-Trip Conversion")
struct RoundTripTests {

    @Test("Round-trip preserves sample count")
    func roundTripPreservesSampleCount() throws {
        let originalSamples: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0]
        let original = MLXArray(originalSamples)

        let wavData = try AudioConversion.mlxArrayToWAVData(original)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        #expect(restored.size == original.size, "Round-trip should preserve sample count")
    }

    @Test("Round-trip preserves sample values within quantization error")
    func roundTripPreservesSamples() throws {
        let originalSamples: [Float] = [0.0, 0.25, -0.25, 0.5, -0.5, 0.75, -0.75]
        let original = MLXArray(originalSamples)

        let wavData = try AudioConversion.mlxArrayToWAVData(original)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let restoredSamples = restored.asArray(Float.self)

        // 16-bit quantization error is at most 1/32768 ≈ 3.05e-5
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6
        for (i, orig) in originalSamples.enumerated() {
            let diff = abs(restoredSamples[i] - orig)
            #expect(diff < maxError, "Sample \(i): expected ~\(orig), got \(restoredSamples[i]), diff=\(diff)")
        }
    }

    @Test("Round-trip with silence produces near-zero samples")
    func roundTripSilence() throws {
        let silence = MLXArray([Float](repeating: 0.0, count: 480))
        let wavData = try AudioConversion.mlxArrayToWAVData(silence)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let samples = restored.asArray(Float.self)
        for (i, sample) in samples.enumerated() {
            #expect(abs(sample) < 1e-4, "Silence sample \(i) should be near zero, got \(sample)")
        }
    }

    @Test("Round-trip with full-scale signals clamps correctly")
    func roundTripFullScale() throws {
        // Values beyond [-1, 1] should be clamped
        let overdriven = MLXArray([-2.0, -1.0, 0.0, 1.0, 2.0] as [Float])
        let wavData = try AudioConversion.mlxArrayToWAVData(overdriven)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let samples = restored.asArray(Float.self)
        // -2.0 clamped to -1.0, 2.0 clamped to 1.0
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6
        #expect(abs(samples[0] - (-1.0)) < maxError, "Clamped -2.0 should be ~-1.0")
        #expect(abs(samples[4] - 1.0) < maxError, "Clamped 2.0 should be ~1.0")
    }

    @Test("Round-trip with 2-D MLXArray flattens correctly")
    func roundTripFlattensBatchDimension() throws {
        let samples2D = MLXArray([Float](repeating: 0.3, count: 100)).reshaped(1, 100)
        let wavData = try AudioConversion.mlxArrayToWAVData(samples2D)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        #expect(restored.ndim == 1, "Restored array should be 1-D")
        #expect(restored.size == 100, "Should have 100 samples after flattening")
    }
}

@Suite("AudioConversion - Edge Cases")
struct EdgeCaseTests {

    @Test("Empty audio produces valid WAV with zero-length data chunk")
    func emptyAudioProducesValidWAV() throws {
        let empty = MLXArray([Float]())
        let wavData = try AudioConversion.mlxArrayToWAVData(empty)

        // Should have 44-byte header with 0-byte data
        #expect(wavData.count == 44, "Empty WAV should be exactly 44 bytes (header only)")

        let dataSize = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataSize == 0, "Empty WAV data chunk size should be 0")
    }

    @Test("Single sample round-trips correctly")
    func singleSampleRoundTrip() throws {
        let single = MLXArray([0.42] as [Float])
        let wavData = try AudioConversion.mlxArrayToWAVData(single)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        #expect(restored.size == 1)
        let value = restored.asArray(Float.self)[0]
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6
        #expect(abs(value - 0.42) < maxError)
    }

    @Test("Medium-length audio (1 second at 24kHz) round-trips correctly")
    func mediumLengthRoundTrip() throws {
        // 1 second of 440Hz sine wave at 24kHz
        let sampleRate = 24000
        let frequency: Float = 440.0
        var samples = [Float](repeating: 0, count: sampleRate)
        for i in 0..<sampleRate {
            samples[i] = sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
        }

        let original = MLXArray(samples)
        let wavData = try AudioConversion.mlxArrayToWAVData(original, sampleRate: sampleRate)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        #expect(restored.size == sampleRate, "Should have \(sampleRate) samples")

        // Verify total WAV size: 44 header + 24000 * 2 bytes = 48044
        #expect(wavData.count == 44 + sampleRate * 2)
    }

    @Test("wavDataToMLXArray rejects data that is too short")
    func rejectsTooShortData() {
        let tooShort = Data([0x00, 0x01, 0x02])
        #expect(throws: VoxAltaError.self) {
            _ = try AudioConversion.wavDataToMLXArray(tooShort)
        }
    }

    @Test("wavDataToMLXArray rejects data without RIFF header")
    func rejectsNonRIFFData() {
        var badData = Data(repeating: 0x00, count: 44)
        // Not a valid RIFF header
        badData[0] = 0x42  // 'B' instead of 'R'
        #expect(throws: VoxAltaError.self) {
            _ = try AudioConversion.wavDataToMLXArray(badData)
        }
    }

    @Test("wavDataToMLXArray rejects data without WAVE marker")
    func rejectsNonWAVEData() throws {
        // Build a valid RIFF header but with wrong format marker
        var badData = Data(repeating: 0x00, count: 44)
        // "RIFF"
        badData[0] = 0x52; badData[1] = 0x49; badData[2] = 0x46; badData[3] = 0x46
        // Not "WAVE"
        badData[8] = 0x41; badData[9] = 0x56; badData[10] = 0x49; badData[11] = 0x20

        #expect(throws: VoxAltaError.self) {
            _ = try AudioConversion.wavDataToMLXArray(badData)
        }
    }
}

@Suite("AudioConversion - buildWAVData Helper")
struct BuildWAVDataTests {

    @Test("buildWAVData produces correct total size")
    func buildWAVDataCorrectSize() {
        let pcm: [Int16] = [0, 100, -100, 200, -200]
        let wav = AudioConversion.buildWAVData(pcmSamples: pcm, sampleRate: 24000)

        // 44 bytes header + 5 samples * 2 bytes = 54
        #expect(wav.count == 54)
    }

    @Test("buildWAVData with empty samples produces header-only WAV")
    func buildWAVDataEmpty() {
        let wav = AudioConversion.buildWAVData(pcmSamples: [], sampleRate: 24000)
        #expect(wav.count == 44)
    }
}
