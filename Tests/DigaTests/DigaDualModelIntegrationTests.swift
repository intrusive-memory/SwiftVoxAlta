import AVFoundation
import Foundation
import Testing

/// Integration tests verifying dual-model audio generation via the diga binary.
///
/// Validates that both 0.6B and 1.7B models produce valid, distinct audio output.
/// Requires: Binary at `./bin/diga`, model caches, Metal GPU support.
@Suite(
  "Dual-Model Audio Generation Integration Tests",
  .serialized,
  .disabled(
    if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil,
    "Metal compiler not supported on GitHub Actions")
)
struct DigaDualModelIntegrationTests {

  /// Result from running diga process.
  struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  // MARK: - Test Cases

  @Test("Both 0.6B and 1.7B models produce valid, distinct audio")
  func dualModelGeneration() async throws {
    let binaryPath = try Self.findBinaryPath()
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("diga-dual-test-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let outputPath0_6b = tempDir.appendingPathComponent("test-0.6b.wav").path
    let outputPath1_7b = tempDir.appendingPathComponent("test-1.7b.wav").path
    let sentence = "The stars shine brightly tonight"

    // Generate with 0.6B model
    let result0_6b = try await Self.runDiga(
      binaryPath: binaryPath,
      args: ["-v", "ryan", "--model", "0.6b", "-o", outputPath0_6b, sentence],
      timeout: 60
    )
    #expect(
      result0_6b.exitCode == 0, "0.6B generation should succeed, stderr: \(result0_6b.stderr)")

    // Generate with 1.7B model
    let result1_7b = try await Self.runDiga(
      binaryPath: binaryPath,
      args: ["-v", "ryan", "--model", "1.7b", "-o", outputPath1_7b, sentence],
      timeout: 60
    )
    #expect(
      result1_7b.exitCode == 0, "1.7B generation should succeed, stderr: \(result1_7b.stderr)")

    // Validate both files exist
    #expect(FileManager.default.fileExists(atPath: outputPath0_6b), "0.6B output should exist")
    #expect(FileManager.default.fileExists(atPath: outputPath1_7b), "1.7B output should exist")

    // Validate WAV headers
    try validateWAVHeaders(path: outputPath0_6b)
    try validateWAVHeaders(path: outputPath1_7b)

    // Validate audio format (24kHz mono)
    let audio0_6b = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath0_6b))
    let audio1_7b = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath1_7b))

    #expect(audio0_6b.processingFormat.sampleRate == 24000, "0.6B should be 24kHz")
    #expect(audio1_7b.processingFormat.sampleRate == 24000, "1.7B should be 24kHz")
    #expect(audio0_6b.processingFormat.channelCount == 1, "0.6B should be mono")
    #expect(audio1_7b.processingFormat.channelCount == 1, "1.7B should be mono")

    // Validate not silence
    let rms0_6b = try calculateRMS(audioFile: audio0_6b)
    let rms1_7b = try calculateRMS(audioFile: audio1_7b)

    #expect(rms0_6b > 0.02, "0.6B audio should not be silence (RMS=\(rms0_6b))")
    #expect(rms1_7b > 0.02, "1.7B audio should not be silence (RMS=\(rms1_7b))")

    // Validate outputs differ (different models should produce different audio)
    let size0_6b =
      try FileManager.default.attributesOfItem(atPath: outputPath0_6b)[.size] as? Int ?? 0
    let size1_7b =
      try FileManager.default.attributesOfItem(atPath: outputPath1_7b)[.size] as? Int ?? 0
    let sizesDiffer = size0_6b != size1_7b
    let rmsDiffers = abs(rms0_6b - rms1_7b) > 0.001

    #expect(
      sizesDiffer || rmsDiffers,
      "Models should produce different output (sizes: \(size0_6b) vs \(size1_7b), RMS: \(rms0_6b) vs \(rms1_7b))"
    )

    print(
      "Dual-model test passed: 0.6B(\(size0_6b)B, RMS=\(String(format: "%.4f", rms0_6b))) vs 1.7B(\(size1_7b)B, RMS=\(String(format: "%.4f", rms1_7b)))"
    )
  }

  // MARK: - Helpers

  private static func findBinaryPath() throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repoRoot =
      testFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let binaryPath =
      repoRoot
      .appendingPathComponent("bin")
      .appendingPathComponent("diga")
      .path

    guard FileManager.default.fileExists(atPath: binaryPath) else {
      throw TestError.binaryNotFound(
        "diga binary not found at \(binaryPath). Run 'make install' to build."
      )
    }
    return binaryPath
  }

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

    return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
      group.addTask {
        await withCheckedContinuation { continuation in
          process.terminationHandler = { process in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(
              returning: ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
              ))
          }
        }
      }

      group.addTask {
        try await Task.sleep(for: .seconds(timeout))
        if process.isRunning { process.terminate() }
        throw TestError.timeout("Process timed out after \(timeout)s")
      }

      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private func validateWAVHeaders(path: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count >= 12 else {
      throw TestError.invalidFile("File too small for WAV headers")
    }
    let riff = String(data: data[0..<4], encoding: .ascii)
    guard riff == "RIFF" else {
      throw TestError.invalidFormat("Missing RIFF header (got: \(riff ?? "nil"))")
    }
    let wave = String(data: data[8..<12], encoding: .ascii)
    guard wave == "WAVE" else {
      throw TestError.invalidFormat("Missing WAVE marker (got: \(wave ?? "nil"))")
    }
  }

  private func calculateRMS(audioFile: AVAudioFile) throws -> Float {
    let format = audioFile.processingFormat
    let frameCount = AVAudioFrameCount(audioFile.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      throw TestError.invalidFile("Could not allocate PCM buffer")
    }
    try audioFile.read(into: buffer)
    guard let floatData = buffer.floatChannelData else {
      throw TestError.invalidFile("Could not access float channel data")
    }
    var sumSquares: Float = 0.0
    for i in 0..<Int(buffer.frameLength) {
      let sample = floatData[0][i]
      sumSquares += sample * sample
    }
    return sqrt(sumSquares / Float(buffer.frameLength))
  }
}
