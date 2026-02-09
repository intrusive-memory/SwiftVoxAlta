import Foundation
import Testing
@testable import diga

// MARK: - AudioFormat Inference Tests

@Suite("AudioFormat Inference Tests")
struct AudioFormatInferenceTests {

    // --- Test 1: .wav extension infers WAV format ---

    @Test(".wav extension infers WAV format")
    func wavExtensionInfersWAV() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.wav")
        #expect(format == .wav)
    }

    // --- Test 2: .aiff extension infers AIFF format ---

    @Test(".aiff extension infers AIFF format")
    func aiffExtensionInfersAIFF() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.aiff")
        #expect(format == .aiff)
    }

    // --- Test 3: .aif extension also infers AIFF format ---

    @Test(".aif extension infers AIFF format")
    func aifExtensionInfersAIFF() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.aif")
        #expect(format == .aiff)
    }

    // --- Test 4: .m4a extension infers M4A format ---

    @Test(".m4a extension infers M4A format")
    func m4aExtensionInfersM4A() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.m4a")
        #expect(format == .m4a)
    }

    // --- Test 5: Unrecognized extension defaults to WAV ---

    @Test("Unrecognized extension defaults to WAV")
    func unrecognizedExtensionDefaultsToWAV() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.bin")
        #expect(format == .wav)
    }

    // --- Test 6: No extension defaults to WAV ---

    @Test("No extension defaults to WAV")
    func noExtensionDefaultsToWAV() {
        let format = AudioFormat.infer(fromPath: "/tmp/outputfile")
        #expect(format == .wav)
    }

    // --- Test 7: --file-format flag overrides extension ---

    @Test("--file-format flag overrides file extension")
    func fileFormatFlagOverridesExtension() {
        // File is .wav but format override says m4a.
        let format = AudioFormat.infer(fromPath: "/tmp/output.wav", formatOverride: "m4a")
        #expect(format == .m4a)
    }

    // --- Test 8: --file-format flag with aiff override ---

    @Test("--file-format aiff overrides .wav extension")
    func fileFormatAIFFOverride() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.wav", formatOverride: "aiff")
        #expect(format == .aiff)
    }

    // --- Test 9: --file-format flag with case insensitivity ---

    @Test("--file-format is case-insensitive")
    func fileFormatCaseInsensitive() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.bin", formatOverride: "M4A")
        #expect(format == .m4a)
    }

    // --- Test 10: Extension inference is case-insensitive ---

    @Test("Extension inference is case-insensitive")
    func extensionCaseInsensitive() {
        let format = AudioFormat.infer(fromPath: "/tmp/output.WAV")
        #expect(format == .wav)
    }
}

// MARK: - AudioFileWriter WAV Output Tests

@Suite("AudioFileWriter WAV Output Tests")
struct AudioFileWriterWAVOutputTests {

    /// Helper: create a minimal valid WAV with known samples.
    private func makeTestWAV(sampleCount: Int = 100) -> Data {
        let samples = (0..<sampleCount).map { Int16($0 % 32767) }
        return WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: 24000)
    }

    /// Helper: create a unique temp directory for a test.
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-audiowriter-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // --- Test 11: WAV write produces valid WAV file with RIFF header ---

    @Test("WAV write produces a valid file with RIFF header")
    func wavWriteProducesValidRIFFHeader() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.wav").path
        let wavData = makeTestWAV()

        try AudioFileWriter.write(wavData: wavData, to: outputPath, format: .wav)

        // Read back and verify RIFF header.
        let written = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        #expect(written.count > 44, "WAV file should be larger than header-only")

        let riff = String(data: written[0..<4], encoding: .ascii)
        #expect(riff == "RIFF", "File should start with RIFF header")

        let wave = String(data: written[8..<12], encoding: .ascii)
        #expect(wave == "WAVE", "File should contain WAVE marker")

        // Data should be identical to input since WAV is a direct write.
        #expect(written == wavData, "WAV output should be identical to input data")
    }

    // --- Test 12: WAV write creates parent directories ---

    @Test("WAV write creates intermediate parent directories")
    func wavWriteCreatesParentDirectories() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let deepPath = tempDir
            .appendingPathComponent("level1")
            .appendingPathComponent("level2")
            .appendingPathComponent("output.wav")
            .path
        let wavData = makeTestWAV(sampleCount: 10)

        try AudioFileWriter.write(wavData: wavData, to: deepPath, format: .wav)

        let exists = FileManager.default.fileExists(atPath: deepPath)
        #expect(exists, "Output file should exist at deeply nested path")
    }
}

// MARK: - AudioFileWriter AIFF Output Tests

@Suite("AudioFileWriter AIFF Output Tests")
struct AudioFileWriterAIFFOutputTests {

    /// Helper: create a minimal valid WAV with known samples.
    private func makeTestWAV(sampleCount: Int = 480) -> Data {
        // Use a reasonable sample count for AIFF conversion.
        let samples = (0..<sampleCount).map { Int16(($0 * 100) % 32767) }
        return WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: 24000)
    }

    /// Helper: create a unique temp directory for a test.
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-audiowriter-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // --- Test 13: AIFF write produces valid AIFF file with FORM header ---

    @Test("AIFF write produces a valid file with FORM header")
    func aiffWriteProducesValidFORMHeader() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.aiff").path
        let wavData = makeTestWAV()

        try AudioFileWriter.write(wavData: wavData, to: outputPath, format: .aiff)

        // Read back and verify FORM/AIFF header.
        let written = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        #expect(written.count > 0, "AIFF file should not be empty")

        let form = String(data: written[0..<4], encoding: .ascii)
        #expect(form == "FORM", "AIFF file should start with FORM header")

        let aiff = String(data: written[8..<12], encoding: .ascii)
        #expect(aiff == "AIFF", "AIFF file should contain AIFF marker")
    }
}

// MARK: - AudioFileWriter M4A Output Tests

@Suite("AudioFileWriter M4A Output Tests")
struct AudioFileWriterM4AOutputTests {

    /// Helper: create a valid WAV with enough samples for AAC encoding.
    private func makeTestWAV(sampleCount: Int = 24000) -> Data {
        // 1 second of audio at 24kHz — enough for AAC encoder.
        let samples = (0..<sampleCount).map { i -> Int16 in
            // Simple sine wave to give the encoder something to work with.
            let phase = Double(i) / Double(sampleCount) * 2.0 * Double.pi * 440.0
            return Int16(clamping: Int(sin(phase) * 16000.0))
        }
        return WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: 24000)
    }

    /// Helper: create a unique temp directory for a test.
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-audiowriter-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // --- Test 14: M4A write produces non-empty file ---

    @Test("M4A write produces a non-empty file")
    func m4aWriteProducesNonEmptyFile() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.m4a").path
        let wavData = makeTestWAV()

        try AudioFileWriter.write(wavData: wavData, to: outputPath, format: .m4a)

        let written = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        #expect(written.count > 0, "M4A file should not be empty")

        // M4A files typically start with an ftyp box or similar MPEG-4 structure.
        // Just verify it's non-trivially sized (AAC has overhead).
        #expect(written.count > 100, "M4A file should have meaningful content")
    }
}

// MARK: - AudioFileWriter Error Handling Tests

@Suite("AudioFileWriter Error Handling Tests")
struct AudioFileWriterErrorTests {

    // --- Test 15: Writing invalid WAV data for AIFF conversion throws ---

    @Test("AIFF conversion with invalid WAV data throws")
    func invalidWAVDataForAIFFThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-audiowriter-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let outputPath = tempDir.appendingPathComponent("bad.aiff").path

        // Data too short to be a valid WAV.
        let badData = Data(repeating: 0, count: 10)

        #expect(throws: AudioFileWriterError.self) {
            try AudioFileWriter.write(wavData: badData, to: outputPath, format: .aiff)
        }
    }

    // --- Test 16: Writing invalid WAV data for M4A conversion throws ---

    @Test("M4A conversion with invalid WAV data throws")
    func invalidWAVDataForM4AThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-audiowriter-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let outputPath = tempDir.appendingPathComponent("bad.m4a").path

        // Data too short to be a valid WAV.
        let badData = Data(repeating: 0, count: 10)

        #expect(throws: AudioFileWriterError.self) {
            try AudioFileWriter.write(wavData: badData, to: outputPath, format: .m4a)
        }
    }
}

// MARK: - AudioFileWriterError Tests

@Suite("AudioFileWriterError Description Tests")
struct AudioFileWriterErrorDescriptionTests {

    // --- Test 17: Error descriptions are human-readable ---

    @Test("AudioFileWriterError provides human-readable descriptions")
    func errorDescriptions() {
        let errors: [AudioFileWriterError] = [
            .invalidWAVData("test detail"),
            .writeFailed("test detail"),
            .conversionFailed("test detail"),
        ]

        for error in errors {
            let desc = error.errorDescription
            #expect(desc != nil, "Error should have a description")
            #expect(desc!.contains("test detail"), "Error description should contain the detail")
        }
    }
}

// MARK: - AudioFormat Enum Tests

@Suite("AudioFormat Enum Tests")
struct AudioFormatEnumTests {

    // --- Test 18: fromExtension handles all known extensions ---

    @Test("fromExtension maps all known extensions correctly")
    func fromExtensionMapsAll() {
        #expect(AudioFormat.fromExtension("wav") == .wav)
        #expect(AudioFormat.fromExtension("aiff") == .aiff)
        #expect(AudioFormat.fromExtension("aif") == .aiff)
        #expect(AudioFormat.fromExtension("m4a") == .m4a)
        #expect(AudioFormat.fromExtension("mp3") == nil)
        #expect(AudioFormat.fromExtension("") == nil)
    }

    // --- Test 19: Raw values match expected strings ---

    @Test("AudioFormat raw values match expected strings")
    func rawValues() {
        #expect(AudioFormat.wav.rawValue == "wav")
        #expect(AudioFormat.aiff.rawValue == "aiff")
        #expect(AudioFormat.m4a.rawValue == "m4a")
    }
}
