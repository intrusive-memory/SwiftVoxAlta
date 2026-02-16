//
//  AudioConversion.swift
//  SwiftVoxAlta
//
//  Utilities for converting between MLXArray audio samples and WAV format Data.
//

import Foundation
@preconcurrency import MLX

/// Utilities for converting between MLXArray float audio samples and WAV format Data.
///
/// All conversions assume mono, 16-bit PCM audio at 24kHz unless otherwise specified.
/// The WAV format uses the standard RIFF/WAVE container with a `fmt ` chunk and `data` chunk.
public enum AudioConversion: Sendable {

    // MARK: - MLXArray → WAV Data

    /// Convert an MLXArray of float audio samples to WAV format Data.
    ///
    /// The input array should contain normalized float samples (typically in the range -1.0 to 1.0).
    /// Samples are clamped to [-1.0, 1.0] before conversion to 16-bit PCM integers.
    ///
    /// - Parameters:
    ///   - audio: An MLXArray of float audio samples. Can be 1-D `[samples]`
    ///     or 2-D `[1, samples]`.
    ///   - sampleRate: The audio sample rate in Hz. Defaults to 24000 (Qwen3-TTS output rate).
    /// - Returns: WAV format Data containing a RIFF header and 16-bit PCM samples.
    /// - Throws: `VoxAltaError.audioExportFailed` if the array cannot be converted.
    public static func mlxArrayToWAVData(_ audio: MLXArray, sampleRate: Int = 24000) throws -> Data {
        // Flatten to 1-D if needed
        var flatAudio = audio
        if flatAudio.ndim > 1 {
            flatAudio = flatAudio.reshaped(-1)
        }

        // Convert to Float32 on CPU
        let floatArray = flatAudio.asType(.float32)
        eval(floatArray)

        // Extract float samples
        let floatSamples: [Float] = floatArray.asArray(Float.self)

        // Convert float samples to 16-bit PCM integers
        let pcmSamples = floatSamples.map { sample -> Int16 in
            guard sample.isFinite else { return 0 }
            let clamped = min(max(sample, -1.0), 1.0)
            return Int16(clamped * Float(Int16.max))
        }

        // Build WAV data
        return buildWAVData(pcmSamples: pcmSamples, sampleRate: sampleRate)
    }

    // MARK: - WAV Data → MLXArray

    /// Parse WAV format Data and return an MLXArray of float audio samples.
    ///
    /// Supports 16-bit PCM WAV files (mono). The returned array contains normalized
    /// float samples in the range [-1.0, 1.0].
    ///
    /// - Parameter data: WAV format Data containing a RIFF header and PCM samples.
    /// - Returns: An MLXArray of float audio samples, shape `[samples]`.
    /// - Throws: `VoxAltaError.audioExportFailed` if the WAV data is invalid or unsupported.
    public static func wavDataToMLXArray(_ data: Data) throws -> MLXArray {
        // Validate minimum WAV size: 44-byte header
        guard data.count >= 44 else {
            throw VoxAltaError.audioExportFailed(
                "WAV data too short (\(data.count) bytes). Minimum header is 44 bytes."
            )
        }

        // Validate RIFF header
        let riffMarker = String(data: data[0..<4], encoding: .ascii)
        guard riffMarker == "RIFF" else {
            throw VoxAltaError.audioExportFailed(
                "Invalid WAV data: missing RIFF header marker."
            )
        }

        let waveMarker = String(data: data[8..<12], encoding: .ascii)
        guard waveMarker == "WAVE" else {
            throw VoxAltaError.audioExportFailed(
                "Invalid WAV data: missing WAVE format marker."
            )
        }

        // Parse fmt chunk — find it by scanning chunks
        let (bitsPerSample, numChannels, dataOffset, dataSize) = try parseFmtAndDataChunks(data)

        guard bitsPerSample == 16 else {
            throw VoxAltaError.audioExportFailed(
                "Unsupported WAV format: \(bitsPerSample)-bit samples. Only 16-bit PCM is supported."
            )
        }

        guard numChannels == 1 else {
            throw VoxAltaError.audioExportFailed(
                "Unsupported WAV format: \(numChannels) channels. Only mono is supported."
            )
        }

        // Extract PCM samples
        let sampleCount = dataSize / 2  // 16-bit = 2 bytes per sample
        guard dataOffset + dataSize <= data.count else {
            throw VoxAltaError.audioExportFailed(
                "WAV data chunk extends beyond file boundary."
            )
        }

        var floatSamples = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { rawBuffer in
            let pcmPtr = rawBuffer.baseAddress!.advanced(by: dataOffset)
                .assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: pcmPtr[i])
                floatSamples[i] = Float(sample) / Float(Int16.max)
            }
        }

        return MLXArray(floatSamples)
    }

    // MARK: - WAV Header Construction

    /// Build a complete WAV file Data from 16-bit PCM samples.
    ///
    /// - Parameters:
    ///   - pcmSamples: Array of 16-bit PCM integer samples.
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: Complete WAV format Data with RIFF header.
    static func buildWAVData(pcmSamples: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = numChannels * bytesPerSample
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcmSamples.count * Int(bytesPerSample))
        let fileSize = 36 + dataSize  // Total file size minus 8 bytes for RIFF header

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(&data, fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendLittleEndian(&data, UInt32(16))          // fmt chunk size
        appendLittleEndian(&data, UInt16(1))            // PCM format
        appendLittleEndian(&data, numChannels)
        appendLittleEndian(&data, UInt32(sampleRate))
        appendLittleEndian(&data, byteRate)
        appendLittleEndian(&data, blockAlign)
        appendLittleEndian(&data, bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(&data, dataSize)

        // PCM samples
        for sample in pcmSamples {
            appendLittleEndian(&data, UInt16(bitPattern: sample))
        }

        return data
    }

    // MARK: - WAV Parsing Helpers

    /// Parse the fmt and data chunks from WAV data.
    ///
    /// - Parameter data: The complete WAV file data.
    /// - Returns: Tuple of (bitsPerSample, numChannels, dataChunkOffset, dataChunkSize).
    /// - Throws: `VoxAltaError.audioExportFailed` if chunks cannot be found.
    private static func parseFmtAndDataChunks(_ data: Data) throws -> (Int, Int, Int, Int) {
        var offset = 12  // Skip RIFF header + "WAVE"
        var bitsPerSample: Int?
        var numChannels: Int?
        var dataOffset: Int?
        var dataSize: Int?

        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize = data.withUnsafeBytes { buffer in
                buffer.load(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
            }

            if chunkID == "fmt " {
                guard offset + 8 + Int(chunkSize) <= data.count, chunkSize >= 16 else {
                    throw VoxAltaError.audioExportFailed("fmt chunk too small or truncated.")
                }
                data.withUnsafeBytes { buffer in
                    numChannels = Int(buffer.load(fromByteOffset: offset + 10, as: UInt16.self).littleEndian)
                    bitsPerSample = Int(buffer.load(fromByteOffset: offset + 22, as: UInt16.self).littleEndian)
                }
            } else if chunkID == "data" {
                dataOffset = offset + 8
                dataSize = Int(chunkSize)
            }

            // Move to next chunk (chunk header is 8 bytes + chunk data)
            offset += 8 + Int(chunkSize)
            // Chunks are word-aligned (padded to even byte boundary)
            if offset % 2 != 0 { offset += 1 }
        }

        guard let bps = bitsPerSample, let nc = numChannels,
              let dOff = dataOffset, let dSize = dataSize else {
            throw VoxAltaError.audioExportFailed(
                "Could not find required fmt and data chunks in WAV data."
            )
        }

        return (bps, nc, dOff, dSize)
    }

    // MARK: - Binary Helpers

    /// Append a value in little-endian byte order to a Data buffer.
    private static func appendLittleEndian<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: MemoryLayout<T>.size))
    }
}
