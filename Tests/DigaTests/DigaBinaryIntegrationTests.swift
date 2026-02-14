import AVFoundation
import Foundation
import Testing

/// Binary integration tests that spawn the diga executable and validate audio output
///
/// These tests require:
/// - Binary built and available at `./bin/diga`
/// - CustomVoice model cached (will auto-download on first run ~3.4GB)
/// - Metal GPU compiler support (not available on GitHub Actions runners)
///
/// Note: These tests are disabled on CI due to Metal compiler compatibility issues.
/// Run locally to verify audio generation functionality.
@Suite(
    "Binary Audio Generation Integration Tests",
    .serialized,
    .disabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "Metal compiler not supported on GitHub Actions")
)
struct DigaBinaryIntegrationTests {

    /// Initialize voice cache if needed (runs once per test suite)
    init() async throws {
        guard !Self.areVoicesCached() else {
            return  // Voices already cached, skip warmup
        }

        print("⏳ First run: Generating voice 'ryan' (~60 seconds)...")
        print("   Subsequent runs will use cached voice and be fast.")

        let binary = try Self.findBinaryPath()
        let result = try await Self.runDiga(
            binaryPath: binary,
            args: ["-v", "ryan", "-o", "/tmp/diga-warmup.wav", "test"],
            timeout: 120  // 2 minute timeout for voice generation
        )

        defer { try? FileManager.default.removeItem(atPath: "/tmp/diga-warmup.wav") }

        guard result.exitCode == 0 else {
            throw TestError.voiceGenerationFailed(
                "Failed to generate voice 'ryan': \(result.stderr)"
            )
        }

        print("✓ Voice 'ryan' cached. Tests will now run fast.")
    }

    /// Check if voices are cached in ~/Library/Caches/intrusive-memory/Voices/
    private static func areVoicesCached() -> Bool {
        let voicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/intrusive-memory/Voices")

        let ryanVoice = voicesDir.appendingPathComponent("ryan.voice")
        return FileManager.default.fileExists(atPath: ryanVoice.path)
    }

    // MARK: - Test Cases

    @Test("Generate valid WAV file with audio data")
    func wavGeneration() async throws {
        print("Testing WAV generation...")

        let binaryPath = try Self.findBinaryPath()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.wav").path

        // Generate audio
        let result = try await Self.runDiga(
            binaryPath: binaryPath,
            args: ["-v", "ryan", "-o", outputPath, "The quick brown fox jumps over the lazy dog"],
            timeout: 30
        )

        // Validate exit code
        #expect(result.exitCode == 0, "diga should exit with code 0")

        // Validate file exists and size
        try validateFileExists(path: outputPath, minSize: 44)

        // Validate headers
        try validateAudioHeaders(path: outputPath, expectedFormat: .wav)

        // Validate audio format
        let audioFile = try validateAudioFormat(path: outputPath)

        // Validate not silence
        try validateNotSilence(audioFile: audioFile)

        print("✓ WAV generation test passed")
    }

    @Test("Generate valid AIFF file")
    func aiffGeneration() async throws {
        print("Testing AIFF generation...")

        let binaryPath = try Self.findBinaryPath()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.aiff").path

        let result = try await Self.runDiga(
            binaryPath: binaryPath,
            args: ["-v", "ryan", "-o", outputPath, "Testing AIFF format"],
            timeout: 30
        )

        #expect(result.exitCode == 0)
        try validateFileExists(path: outputPath, minSize: 54)
        try validateAudioHeaders(path: outputPath, expectedFormat: .aiff)
        let audioFile = try validateAudioFormat(path: outputPath)
        try validateNotSilence(audioFile: audioFile)

        print("✓ AIFF generation test passed")
    }

    @Test("Generate valid M4A file")
    func m4aGeneration() async throws {
        print("Testing M4A generation...")

        let binaryPath = try Self.findBinaryPath()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("test.m4a").path

        let result = try await Self.runDiga(
            binaryPath: binaryPath,
            args: ["-v", "ryan", "-o", outputPath, "Testing M4A format"],
            timeout: 30
        )

        #expect(result.exitCode == 0)
        try validateFileExists(path: outputPath, minSize: 100)
        try validateAudioHeaders(path: outputPath, expectedFormat: .m4a)
        let audioFile = try validateAudioFormat(path: outputPath)
        try validateNotSilence(audioFile: audioFile)

        print("✓ M4A generation test passed")
    }

    @Test("Gracefully handle binary not found")
    func binaryNotFoundHandling() async throws {
        print("Testing binary not found error handling...")

        // Use a non-existent binary path
        do {
            _ = try await Self.runDiga(
                binaryPath: "/nonexistent/path/to/diga",
                args: ["-o", "/tmp/test.wav", "test"],
                timeout: 5
            )
            Issue.record("Expected process to fail with binary not found")
        } catch {
            // Expected to throw
            #expect(error is TestError || error is CocoaError)
            print("✓ Binary not found correctly handled")
        }
    }

    // MARK: - Binary Path Resolution

    /// Find the diga binary by navigating from test file path
    ///
    /// Working directory during tests is /private/tmp, NOT the repo root.
    /// We use #filePath (absolute path to this test file) to navigate to repo root.
    private static func findBinaryPath() throws -> String {
        // #filePath is absolute: /Users/.../SwiftVoxAlta/Tests/DigaTests/DigaBinaryIntegrationTests.swift
        let testFileURL = URL(fileURLWithPath: #filePath)

        // Navigate up to repo root: Tests/DigaTests -> Tests -> SwiftVoxAlta
        let repoRoot = testFileURL
            .deletingLastPathComponent()  // Remove DigaBinaryIntegrationTests.swift
            .deletingLastPathComponent()  // Remove DigaTests
            .deletingLastPathComponent()  // Remove Tests

        let binaryPath = repoRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("diga")
            .path

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw TestError.binaryNotFound(
                "diga binary not found at \(binaryPath). " +
                "Run 'make install' to build the binary."
            )
        }

        return binaryPath
    }

    // MARK: - Process Spawning

    /// Result from running diga process
    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Run diga binary with arguments and timeout
    ///
    /// Uses async/await with TaskGroup to race process completion vs timeout.
    private static func runDiga(
        binaryPath: String,
        args: [String],
        timeout: TimeInterval = 30
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Race between process completion and timeout
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            // Task 1: Wait for process to complete
            group.addTask {
                await withCheckedContinuation { continuation in
                    process.terminationHandler = { process in
                        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                        continuation.resume(returning: ProcessResult(
                            exitCode: process.terminationStatus,
                            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                            stderr: String(data: stderrData, encoding: .utf8) ?? ""
                        ))
                    }
                }
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
                throw TestError.timeout("Process timed out after \(timeout)s")
            }

            // Return first result, cancel other task
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - File Validation

    /// Audio format enum for header validation
    enum AudioFormat {
        case wav
        case aiff
        case m4a
    }

    /// Validate that audio file exists and has non-zero size
    private func validateFileExists(path: String, minSize: Int = 44) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw TestError.fileNotFound("Audio file not created at \(path)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)

        guard let fileSize = attributes[.size] as? Int, fileSize > minSize else {
            let actualSize = attributes[.size] as? Int ?? 0
            throw TestError.invalidFile(
                "File size (\(actualSize) bytes) is too small (expected > \(minSize) bytes)"
            )
        }
    }

    /// Validate audio file magic bytes/headers
    private func validateAudioHeaders(path: String, expectedFormat: AudioFormat) throws {
        let url = URL(fileURLWithPath: path)
        let fileData = try Data(contentsOf: url)

        guard fileData.count >= 12 else {
            throw TestError.invalidFile("File too small to contain valid headers")
        }

        switch expectedFormat {
        case .wav:
            // Check for "RIFF" at offset 0
            let riff = String(data: fileData[0..<4], encoding: .ascii)
            guard riff == "RIFF" else {
                throw TestError.invalidFormat("Missing RIFF header (got: \(riff ?? "nil"))")
            }

            // Check for "WAVE" at offset 8
            let wave = String(data: fileData[8..<12], encoding: .ascii)
            guard wave == "WAVE" else {
                throw TestError.invalidFormat("Missing WAVE format marker (got: \(wave ?? "nil"))")
            }

        case .aiff:
            // Check for "FORM" at offset 0
            let form = String(data: fileData[0..<4], encoding: .ascii)
            guard form == "FORM" else {
                throw TestError.invalidFormat("Missing FORM header (got: \(form ?? "nil"))")
            }

            // Check for "AIFF" at offset 8
            let aiff = String(data: fileData[8..<12], encoding: .ascii)
            guard aiff == "AIFF" else {
                throw TestError.invalidFormat("Missing AIFF format marker (got: \(aiff ?? "nil"))")
            }

        case .m4a:
            // M4A files have ftyp box at offset 4-8
            let ftyp = String(data: fileData[4..<8], encoding: .ascii)
            guard ftyp == "ftyp" else {
                throw TestError.invalidFormat("Missing ftyp box for M4A (got: \(ftyp ?? "nil"))")
            }
        }
    }

    /// Validate audio format using AVAudioFile
    private func validateAudioFormat(path: String) throws -> AVAudioFile {
        let url = URL(fileURLWithPath: path)
        let audioFile = try AVAudioFile(forReading: url)

        let format = audioFile.processingFormat

        // Validate sample rate (expected: 24000 Hz)
        guard format.sampleRate == 24000 else {
            throw TestError.invalidFormat(
                "Expected 24kHz sample rate, got \(format.sampleRate)Hz"
            )
        }

        // Validate channel count (expected: 1 = mono)
        guard format.channelCount == 1 else {
            throw TestError.invalidFormat(
                "Expected mono (1 channel), got \(format.channelCount) channels"
            )
        }

        return audioFile
    }

    // MARK: - Silence Detection

    /// Detect if audio contains only silence (all samples near zero)
    ///
    /// Thresholds empirically validated:
    /// - RMS > 0.02: Detects signals 10× below typical speech (0.21-0.42)
    /// - Peak > 0.1: Detects signals 3× below typical speech (0.3-0.6)
    private func validateNotSilence(audioFile: AVAudioFile) throws {
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.invalidFile("Could not allocate PCM buffer")
        }

        try audioFile.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            throw TestError.invalidFile("Could not access float channel data")
        }

        // Calculate RMS (root mean square) level
        var sumSquares: Float = 0.0
        var peakAmplitude: Float = 0.0

        for i in 0..<Int(buffer.frameLength) {
            let sample = floatData[0][i]
            sumSquares += sample * sample
            peakAmplitude = max(peakAmplitude, abs(sample))
        }

        let rms = sqrt(sumSquares / Float(buffer.frameLength))

        // Log values for debugging
        print("  Audio analysis: RMS=\(String(format: "%.4f", rms)), " +
              "Peak=\(String(format: "%.4f", peakAmplitude)), " +
              "Frames=\(buffer.frameLength)")

        // Empirically validated thresholds (huge safety margins)
        // Speech audio: RMS ~0.21-0.42, Peak ~0.3-0.6
        let rmsThreshold: Float = 0.02   // 10× below typical speech
        let peakThreshold: Float = 0.1   // 3× below typical speech

        guard rms > rmsThreshold else {
            throw TestError.silenceDetected(
                "Audio RMS (\(String(format: "%.4f", rms))) is below threshold (\(rmsThreshold))"
            )
        }

        guard peakAmplitude > peakThreshold else {
            throw TestError.silenceDetected(
                "Audio peak amplitude (\(String(format: "%.4f", peakAmplitude))) is below threshold (\(peakThreshold))"
            )
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during binary integration tests
enum TestError: Error, LocalizedError {
    case binaryNotFound(String)
    case fileNotFound(String)
    case invalidFile(String)
    case invalidFormat(String)
    case silenceDetected(String)
    case timeout(String)
    case voiceGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let detail): return "Binary not found: \(detail)"
        case .fileNotFound(let detail): return "File not found: \(detail)"
        case .invalidFile(let detail): return "Invalid file: \(detail)"
        case .invalidFormat(let detail): return "Invalid format: \(detail)"
        case .silenceDetected(let detail): return "Silence detected: \(detail)"
        case .timeout(let detail): return "Timeout: \(detail)"
        case .voiceGenerationFailed(let detail): return "Voice generation failed: \(detail)"
        }
    }
}
