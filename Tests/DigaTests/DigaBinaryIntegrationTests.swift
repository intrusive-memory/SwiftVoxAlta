import Foundation
import SwiftAcervo
import Testing

@testable import diga

/// End-to-end binary integration tests.
///
/// These exercise the built `./bin/diga` executable as a subprocess, running an
/// actual TTS synthesis against the cached Qwen3-TTS model and asserting the
/// produced WAV file is structurally sound and non-empty.
///
/// Prerequisites (enforced by the Makefile `test-integration` target):
/// - `./bin/diga` exists (run `make install` or `make release`)
/// - The CustomVoice model is cached (run `make setup-voices` once)
///
/// These start as smoke checks ("does it produce real audio?"). Spectral /
/// timbre comparisons against a reference clip can be layered on later once
/// determinism characteristics of mlx-audio-swift are established.
@Suite("Diga Binary Integration Tests")
struct DigaBinaryIntegrationTests {

  // MARK: - Path helpers

  /// Project root, derived from this file's location.
  /// Tests/DigaTests/DigaBinaryIntegrationTests.swift -> three parents up.
  private var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // DigaTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // project root
  }

  private var binaryURL: URL {
    projectRoot.appendingPathComponent("bin/diga")
  }

  /// Reference test phrase. Long enough to produce ≥ ~1.5s of speech but short
  /// enough to keep the test fast.
  private static let testPhrase = "The quick brown fox jumps over the lazy dog."

  /// Default voice for synthesis. Matches the Makefile `setup-voices` warmup.
  private static let testVoice = "ryan"

  // MARK: - Subprocess helper

  private struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  /// Run the diga binary with the given args, capturing exit code and output.
  private func runDiga(_ args: [String], timeout: TimeInterval = 180) throws -> ProcessResult {
    let process = Process()
    process.executableURL = binaryURL
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Enforce timeout — synthesis on first run can take a while if Metal needs
    // to JIT-compile shaders, but a stuck process should not hang CI.
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning {
      process.terminate()
      Issue.record("diga subprocess timed out after \(timeout)s; terminated.")
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
      exitCode: process.terminationStatus,
      stdout: String(data: stdoutData, encoding: .utf8) ?? "",
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
  }

  // MARK: - Smoke tests (no model required)

  @Test("Binary exists at ./bin/diga")
  func binaryExists() {
    let exists = FileManager.default.isExecutableFile(atPath: binaryURL.path)
    #expect(
      exists,
      """
      diga binary not found or not executable at \(binaryURL.path).
      Run `make install` or `make release` first.
      """
    )
  }

  @Test("--version reports a non-empty semver string")
  func versionFlag() throws {
    let result = try runDiga(["--version"])
    #expect(
      result.exitCode == 0, "diga --version exited \(result.exitCode). stderr: \(result.stderr)")
    let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(!trimmed.isEmpty, "diga --version produced no output")
    // Output is "diga <semver>" — match the semver token anywhere in the line.
    let semverPattern = #"\b\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?\b"#
    let regex = try? NSRegularExpression(pattern: semverPattern)
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    let match = regex?.firstMatch(in: trimmed, range: range)
    #expect(match != nil, "diga --version output '\(trimmed)' does not contain a semver token")
  }

  // MARK: - Full synthesis (requires cached model)

  @Test("Synthesis produces a non-empty, well-formed WAV file")
  func synthesisProducesValidWAV() throws {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("diga-integ-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let result = try runDiga([
      "-v", Self.testVoice,
      "-o", outputURL.path,
      Self.testPhrase,
    ])

    // If the model can't be loaded (not cached, or cache permission issue),
    // skip cleanly with an actionable warning rather than failing. The
    // Makefile target documents `make setup-voices` as the explicit prereq;
    // a missing model is a configuration state, not a code regression.
    let modelLoadFailed =
      result.stderr.contains("Model not available")
      || result.stderr.contains("permission to save")
    if modelLoadFailed {
      // Ask Acervo for the path it would actually use — never hardcode.
      let acervoPath = Acervo.sharedModelsDirectory.path
      print(
        """
        [diga integration] SKIPPED — TTS model could not be loaded.
        Run `make setup-voices` to download the model, and ensure the
        Acervo-resolved cache directory is writable by the current user:
            \(acervoPath)
        Raw stderr: \(result.stderr.prefix(500))
        """
      )
      return
    }

    #expect(
      result.exitCode == 0,
      "diga exited \(result.exitCode).\nstdout: \(result.stdout)\nstderr: \(result.stderr)"
    )

    // File exists and is non-trivially sized. WAV header alone is 44 bytes;
    // a 5 KB floor comfortably rules out header-only / zero-payload outputs.
    let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
    let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
    #expect(fileSize > 5_000, "Output WAV is suspiciously small (\(fileSize) bytes)")

    // Header must parse and PCM payload must be non-zero.
    let data = try Data(contentsOf: outputURL)
    let header = try WAVHeaderParser.parse(data)
    #expect(header.dataSize > 0, "WAV reports zero PCM bytes")
    #expect(header.sampleRate > 0, "WAV header reports zero sample rate")
    #expect(header.numChannels > 0, "WAV header reports zero channels")
    #expect(header.bitsPerSample == 16, "Expected 16-bit PCM")

    // Duration sanity: our phrase should yield at least ~0.5 s of audio.
    // dataSize / (sampleRate * channels * bytesPerSample) = duration
    let bytesPerSample = Int(header.bitsPerSample) / 8
    let totalSamples =
      Int(header.dataSize) / (Int(header.numChannels) * max(bytesPerSample, 1))
    let duration = Double(totalSamples) / Double(header.sampleRate)
    #expect(
      duration >= 0.5,
      "Audio duration \(duration)s is below 0.5s floor — likely truncated or silent"
    )
  }
}
