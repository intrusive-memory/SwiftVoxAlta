import AVFoundation
import Foundation

// MARK: - AudioFormat

/// Supported output audio file formats for the diga CLI.
enum AudioFormat: String, Sendable, CaseIterable {
    case wav
    case aiff
    case m4a

    /// All recognized file extensions mapped to their format.
    /// Includes aliases like `.aif` for AIFF.
    static func fromExtension(_ ext: String) -> AudioFormat? {
        switch ext.lowercased() {
        case "wav":
            return .wav
        case "aiff", "aif":
            return .aiff
        case "m4a":
            return .m4a
        default:
            return nil
        }
    }

    /// Infer the audio format from an output file path.
    ///
    /// If `formatOverride` is provided (from `--file-format` flag), that takes precedence.
    /// Otherwise, the file extension is used. If the extension is not recognized,
    /// defaults to `.wav`.
    ///
    /// - Parameters:
    ///   - path: The output file path.
    ///   - formatOverride: Optional format string from `--file-format` flag.
    /// - Returns: The resolved `AudioFormat`.
    static func infer(fromPath path: String, formatOverride: String? = nil) -> AudioFormat {
        // If an explicit format override is provided, use it.
        if let override = formatOverride {
            if let format = AudioFormat(rawValue: override.lowercased()) {
                return format
            }
            // Also try the extension-based lookup for aliases like "aif".
            if let format = fromExtension(override) {
                return format
            }
        }

        // Infer from the file extension.
        let ext = (path as NSString).pathExtension
        if let format = fromExtension(ext) {
            return format
        }

        // Default to WAV if extension is not recognized.
        return .wav
    }
}

// MARK: - AudioFileWriterError

/// Errors produced by the audio file writer.
enum AudioFileWriterError: Error, LocalizedError, Sendable {
    /// The input WAV data could not be read as a valid audio buffer.
    case invalidWAVData(String)

    /// Writing the output file failed.
    case writeFailed(String)

    /// Audio format conversion failed.
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidWAVData(let detail):
            return "Invalid WAV data: \(detail)"
        case .writeFailed(let detail):
            return "File write failed: \(detail)"
        case .conversionFailed(let detail):
            return "Audio conversion failed: \(detail)"
        }
    }
}

// MARK: - AudioFileWriter

/// Writes WAV audio data to disk in various formats.
///
/// Supports direct WAV passthrough (no conversion), AIFF conversion via `AVAudioFile`,
/// and M4A (AAC) conversion via `AVAudioFile` with compressed settings.
///
/// The input is always 16-bit PCM WAV data at 24kHz mono, as produced by `DigaEngine`.
enum AudioFileWriter: Sendable {

    /// Write WAV data to a file in the specified audio format.
    ///
    /// - Parameters:
    ///   - wavData: The source WAV PCM data (16-bit, 24kHz, mono).
    ///   - path: The output file path.
    ///   - format: The target audio format.
    /// - Throws: `AudioFileWriterError` if writing or conversion fails.
    static func write(wavData: Data, to path: String, format: AudioFormat) throws {
        switch format {
        case .wav:
            try writeWAV(wavData: wavData, to: path)
        case .aiff:
            try writeAIFF(wavData: wavData, to: path)
        case .m4a:
            try writeM4A(wavData: wavData, to: path)
        }
    }

    // MARK: - WAV (direct write)

    /// Write WAV data directly to disk with no conversion.
    private static func writeWAV(wavData: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)

        // Ensure the parent directory exists.
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        do {
            try wavData.write(to: url, options: .atomic)
        } catch {
            throw AudioFileWriterError.writeFailed(
                "Could not write WAV to \(path): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - AIFF (convert via AVAudioFile)

    /// Convert WAV data to AIFF format and write to disk.
    private static func writeAIFF(wavData: Data, to path: String) throws {
        let pcmBuffer = try extractPCMBuffer(from: wavData)
        let outputURL = URL(fileURLWithPath: path)

        // Ensure the parent directory exists.
        let parentDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        do {
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: pcmBuffer.format.sampleRate,
                    AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: true,
                    AVLinearPCMIsFloatKey: false,
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: pcmBuffer)
        } catch let error as AudioFileWriterError {
            throw error
        } catch {
            throw AudioFileWriterError.conversionFailed(
                "AIFF conversion failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - M4A (convert via AVAudioFile with AAC)

    /// Convert WAV data to M4A (AAC) format and write to disk.
    private static func writeM4A(wavData: Data, to path: String) throws {
        let pcmBuffer = try extractPCMBuffer(from: wavData)
        let outputURL = URL(fileURLWithPath: path)

        // Ensure the parent directory exists.
        let parentDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        do {
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: pcmBuffer.format.sampleRate,
                    AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                    AVEncoderBitRateKey: 128_000,
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: pcmBuffer)
        } catch let error as AudioFileWriterError {
            throw error
        } catch {
            throw AudioFileWriterError.conversionFailed(
                "M4A conversion failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - PCM Buffer Extraction

    /// Extract a PCM audio buffer from WAV data by writing to a temp file and reading back.
    ///
    /// AVAudioFile requires a file URL to read from, so we write the WAV data to a
    /// temporary file, read it into an `AVAudioPCMBuffer`, then clean up.
    ///
    /// - Parameter wavData: The source WAV data (16-bit PCM, 24kHz, mono).
    /// - Returns: An `AVAudioPCMBuffer` containing the audio samples.
    /// - Throws: `AudioFileWriterError` if the data is invalid or reading fails.
    private static func extractPCMBuffer(from wavData: Data) throws -> AVAudioPCMBuffer {
        // Validate minimum WAV header size.
        guard wavData.count > WAVConcatenator.standardHeaderSize else {
            throw AudioFileWriterError.invalidWAVData(
                "Data is too short (\(wavData.count) bytes) to contain a valid WAV header."
            )
        }

        // Write WAV data to a temporary file so AVAudioFile can read it.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-convert-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try wavData.write(to: tempURL, options: .atomic)
        } catch {
            throw AudioFileWriterError.invalidWAVData(
                "Could not write temp WAV file: \(error.localizedDescription)"
            )
        }

        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: tempURL)
        } catch {
            throw AudioFileWriterError.invalidWAVData(
                "AVAudioFile could not read WAV data: \(error.localizedDescription)"
            )
        }

        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioFileWriterError.invalidWAVData(
                "Could not allocate PCM buffer for \(frameCount) frames."
            )
        }

        do {
            try inputFile.read(into: buffer)
        } catch {
            throw AudioFileWriterError.invalidWAVData(
                "Could not read PCM data from WAV: \(error.localizedDescription)"
            )
        }

        return buffer
    }
}
