import AVFoundation
import Foundation

// MARK: - AudioPlaybackError

/// Errors specific to audio playback operations.
enum AudioPlaybackError: Error, LocalizedError, Sendable {
    /// The WAV data is too short to contain a valid header.
    case invalidWAVData(String)

    /// Failed to create an audio format from the WAV header parameters.
    case unsupportedFormat(String)

    /// Failed to create a PCM buffer from the audio data.
    case bufferCreationFailed(String)

    /// The audio engine failed to start.
    case engineStartFailed(String)

    /// Playback was interrupted or failed unexpectedly.
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidWAVData(let detail):
            return "Invalid WAV data: \(detail)"
        case .unsupportedFormat(let detail):
            return "Unsupported audio format: \(detail)"
        case .bufferCreationFailed(let detail):
            return "Failed to create audio buffer: \(detail)"
        case .engineStartFailed(let detail):
            return "Audio engine failed to start: \(detail)"
        case .playbackFailed(let detail):
            return "Playback failed: \(detail)"
        }
    }
}

// MARK: - WAVHeader

/// Parsed WAV file header containing audio format parameters.
struct WAVHeader: Sendable, Equatable {
    /// Sample rate in Hz (e.g., 24000).
    let sampleRate: UInt32
    /// Number of audio channels (e.g., 1 for mono).
    let numChannels: UInt16
    /// Bits per sample (e.g., 16).
    let bitsPerSample: UInt16
    /// Byte offset where PCM data begins (typically 44).
    let dataOffset: Int
    /// Size of the PCM data in bytes.
    let dataSize: UInt32
}

// MARK: - WAVHeaderParser

/// Parses WAV file headers to extract audio format parameters.
enum WAVHeaderParser: Sendable {

    /// The minimum size of a standard WAV header (RIFF + fmt + data chunk headers).
    static let minimumHeaderSize = 44

    /// Parse a WAV header from raw data.
    ///
    /// Validates the RIFF/WAVE container markers and extracts format parameters
    /// from the fmt chunk. Supports standard 44-byte headers as produced by
    /// `WAVConcatenator.buildWAVData`.
    ///
    /// - Parameter data: The WAV file data (must be at least 44 bytes).
    /// - Returns: A `WAVHeader` with the parsed format parameters.
    /// - Throws: `AudioPlaybackError.invalidWAVData` if the data is malformed.
    static func parse(_ data: Data) throws -> WAVHeader {
        guard data.count >= minimumHeaderSize else {
            throw AudioPlaybackError.invalidWAVData(
                "Data too short (\(data.count) bytes). Expected at least \(minimumHeaderSize) bytes."
            )
        }

        // Validate RIFF marker
        let riff = String(data: data[0..<4], encoding: .ascii)
        guard riff == "RIFF" else {
            throw AudioPlaybackError.invalidWAVData("Missing RIFF marker.")
        }

        // Validate WAVE marker
        let wave = String(data: data[8..<12], encoding: .ascii)
        guard wave == "WAVE" else {
            throw AudioPlaybackError.invalidWAVData("Missing WAVE marker.")
        }

        // Validate fmt chunk marker
        let fmt = String(data: data[12..<16], encoding: .ascii)
        guard fmt == "fmt " else {
            throw AudioPlaybackError.invalidWAVData("Missing fmt chunk marker.")
        }

        // Parse fmt chunk fields
        let audioFormat = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt16.self).littleEndian }
        guard audioFormat == 1 else {
            throw AudioPlaybackError.invalidWAVData("Not PCM format (audioFormat=\(audioFormat)).")
        }

        let numChannels = data.withUnsafeBytes { $0.load(fromByteOffset: 22, as: UInt16.self).littleEndian }
        let sampleRate = data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self).littleEndian }
        let bitsPerSample = data.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt16.self).littleEndian }

        // Validate data chunk marker
        let dataMarker = String(data: data[36..<40], encoding: .ascii)
        guard dataMarker == "data" else {
            throw AudioPlaybackError.invalidWAVData("Missing data chunk marker.")
        }

        let dataSize = data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self).littleEndian }

        return WAVHeader(
            sampleRate: sampleRate,
            numChannels: numChannels,
            bitsPerSample: bitsPerSample,
            dataOffset: minimumHeaderSize,
            dataSize: dataSize
        )
    }
}

// MARK: - AudioPlayback

/// Plays WAV audio data through the system's default audio output device.
///
/// Uses `AVAudioEngine` and `AVAudioPlayerNode` for real-time playback.
/// Supports both single-buffer playback and streaming chunked playback
/// where synthesis of chunk N+1 overlaps with playback of chunk N.
///
/// All methods are static and create their own engine instances, ensuring
/// thread safety and avoiding state leaks between playback sessions.
final class AudioPlayback: Sendable {

    // MARK: - PCM Buffer Creation

    /// Create an `AVAudioPCMBuffer` from WAV data.
    ///
    /// Parses the WAV header and copies the raw PCM samples into an
    /// `AVAudioPCMBuffer` suitable for scheduling on an `AVAudioPlayerNode`.
    ///
    /// - Parameter wavData: Complete WAV file data (header + PCM samples).
    /// - Returns: A tuple of the audio format and filled PCM buffer.
    /// - Throws: `AudioPlaybackError` if the WAV data is invalid or the buffer cannot be created.
    static func createPCMBuffer(from wavData: Data) throws -> (AVAudioFormat, AVAudioPCMBuffer) {
        let header = try WAVHeaderParser.parse(wavData)

        guard header.bitsPerSample == 16 else {
            throw AudioPlaybackError.unsupportedFormat(
                "Only 16-bit PCM is supported, got \(header.bitsPerSample)-bit."
            )
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(header.sampleRate),
            channels: AVAudioChannelCount(header.numChannels),
            interleaved: false
        ) else {
            throw AudioPlaybackError.unsupportedFormat(
                "Could not create AVAudioFormat for sampleRate=\(header.sampleRate), channels=\(header.numChannels)."
            )
        }

        let bytesPerSample = Int(header.bitsPerSample) / 8
        let frameCount = Int(header.dataSize) / (bytesPerSample * Int(header.numChannels))

        guard frameCount > 0 else {
            throw AudioPlaybackError.bufferCreationFailed("WAV data contains zero frames.")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw AudioPlaybackError.bufferCreationFailed(
                "Could not allocate AVAudioPCMBuffer with \(frameCount) frames."
            )
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Convert 16-bit integer PCM samples to 32-bit float samples.
        guard let floatChannelData = buffer.floatChannelData else {
            throw AudioPlaybackError.bufferCreationFailed("Could not access float channel data.")
        }

        let dataOffset = header.dataOffset
        wavData.withUnsafeBytes { rawBuffer in
            let pcmStart = rawBuffer.baseAddress!.advanced(by: dataOffset)
                .assumingMemoryBound(to: Int16.self)
            let channelCount = Int(header.numChannels)

            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    let sampleIndex = frame * channelCount + channel
                    let intSample = pcmStart[sampleIndex].littleEndian
                    // Normalize Int16 range [-32768, 32767] to Float range [-1.0, 1.0]
                    floatChannelData[channel][frame] = Float(intSample) / 32768.0
                }
            }
        }

        return (format, buffer)
    }

    // MARK: - Single Buffer Playback

    /// Play WAV data through the default system audio output device.
    ///
    /// Parses the WAV header, creates a PCM buffer, schedules it on an
    /// `AVAudioPlayerNode`, starts the engine, and waits for playback to complete.
    ///
    /// - Parameter wavData: Complete WAV file data (header + PCM samples).
    /// - Throws: `AudioPlaybackError` if playback fails or audio hardware is unavailable.
    static func play(wavData: Data) async throws {
        let (format, buffer) = try createPCMBuffer(from: wavData)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            throw AudioPlaybackError.engineStartFailed(error.localizedDescription)
        }

        // Schedule the buffer and wait for playback completion.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer, at: nil, options: []) {
                continuation.resume()
            }
            playerNode.play()
        }

        playerNode.stop()
        engine.stop()
    }

    // MARK: - Streaming Chunked Playback

    /// Play a stream of WAV audio chunks through the default system audio output device.
    ///
    /// As each chunk arrives from the async stream, its PCM buffer is scheduled
    /// immediately on the player node without waiting for previous buffers to finish.
    /// This allows synthesis of chunk N+1 to overlap with playback of chunk N,
    /// providing gapless streaming playback.
    ///
    /// All chunks must share the same audio format (sample rate, channels, bit depth).
    /// The method returns only after all scheduled buffers have been fully played.
    ///
    /// - Parameter chunks: An `AsyncStream<Data>` yielding complete WAV data segments.
    /// - Throws: `AudioPlaybackError` if playback fails or audio hardware is unavailable.
    static func playChunks(chunks: AsyncStream<Data>) async throws {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()

        var engineStarted = false
        var connectedFormat: AVAudioFormat?

        // Track buffer completions so we can wait for the last buffer to finish.
        // Each scheduled buffer gets a continuation that fires when the buffer is consumed.
        // We collect these and await the final one after all chunks are scheduled.
        let completionCounter = CompletionCounter()

        for await wavData in chunks {
            let (format, buffer) = try createPCMBuffer(from: wavData)

            // On first chunk, set up and start the audio engine.
            if !engineStarted {
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                connectedFormat = format

                do {
                    try engine.start()
                } catch {
                    throw AudioPlaybackError.engineStartFailed(error.localizedDescription)
                }

                playerNode.play()
                engineStarted = true
            } else {
                // Validate format consistency across chunks.
                if let existing = connectedFormat,
                   existing.sampleRate != format.sampleRate ||
                   existing.channelCount != format.channelCount {
                    throw AudioPlaybackError.unsupportedFormat(
                        "Chunk format mismatch: expected \(existing.sampleRate)Hz/\(existing.channelCount)ch, " +
                        "got \(format.sampleRate)Hz/\(format.channelCount)ch."
                    )
                }
            }

            // Schedule buffer immediately (non-blocking) for gapless playback.
            // The completion handler increments the counter when the buffer is consumed.
            await completionCounter.increment()
            playerNode.scheduleBuffer(buffer, at: nil, options: []) {
                Task {
                    await completionCounter.decrement()
                }
            }
        }

        // If no chunks arrived, nothing to clean up.
        guard engineStarted else { return }

        // Wait for all scheduled buffers to be fully consumed by the audio engine.
        await completionCounter.waitForAll()

        playerNode.stop()
        engine.stop()
    }
}

// MARK: - CompletionCounter

/// Thread-safe counter that tracks in-flight buffer completions.
///
/// Used by `playChunks` to wait until all scheduled audio buffers have been
/// consumed by the audio engine before stopping playback.
private actor CompletionCounter {
    private var count: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Increment the pending buffer count.
    func increment() {
        count += 1
    }

    /// Decrement the pending buffer count. If it reaches zero, resume any waiters.
    func decrement() {
        count -= 1
        if count <= 0 {
            for waiter in waiters {
                waiter.resume()
            }
            waiters.removeAll()
        }
    }

    /// Wait until all pending buffers have completed.
    /// Returns immediately if no buffers are pending.
    func waitForAll() async {
        if count <= 0 { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }
}
