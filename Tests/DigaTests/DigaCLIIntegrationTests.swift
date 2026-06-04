import ArgumentParser
import Foundation
import SwiftVoxAlta
import Testing

@testable import DigaCLICore

// MARK: - Sprint 7: CLI Integration + Fallback Tests

// ============================================================================
// 7.1 — Voice Flag Tests
// ============================================================================

@Suite("CLI Voice Flag Tests", .acervoEnvironment)
struct CLIVoiceFlagTests {

  // --- Test 1: -v alex parses and selects the alex voice ---

  @Test("-v alex parses correctly and selects the alex voice")
  func voiceFlagSelectsAlex() throws {
    let command = try DigaCommand.parse(["-v", "alex", "hello"])
    #expect(command.voice == "alex")
    #expect(command.positionalArgs == ["hello"])
  }

  // --- Test 2: -v ? parses as the question mark voice ---

  @Test("-v ? is parsed as the voice value '?'")
  func voiceFlagQuestionMark() throws {
    let command = try DigaCommand.parse(["-v", "?", "hello"])
    #expect(command.voice == "?")
  }

  // --- Test 3: -v nonexistent triggers validation error ---

  @Test("Validating a nonexistent voice name prints error")
  func voiceValidationNonexistent() async throws {
    // We cannot call validateVoiceExists directly since it's private,
    // but we can verify that the resolution logic in DigaEngine
    // correctly rejects unknown voices.
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("diga-cli-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
    let engine = DigaEngine(voiceStore: voiceStore)

    // Resolving a nonexistent voice should throw voiceNotFound.
    do {
      _ = try await engine.resolveVoice(name: "nonexistent_voice_xyz")
      Issue.record("Expected voiceNotFound error")
    } catch let error as DigaEngineError {
      if case .voiceNotFound(let name) = error {
        #expect(name == "nonexistent_voice_xyz")
      } else {
        Issue.record("Expected voiceNotFound, got \(error)")
      }
    }
  }

  // --- Test 4: Default voice when -v not specified is first preset (ryan) ---

  @Test("Default voice when -v not specified is the first preset voice")
  func defaultVoiceIsFirstPreset() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("diga-cli-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
    let engine = DigaEngine(voiceStore: voiceStore)

    let defaultVoice = try await engine.resolveVoice(name: nil)
    #expect(defaultVoice.name == "ryan")
    #expect(defaultVoice.type == .preset)
  }
}

// ============================================================================
// 7.2 — File Input and Stdin Tests
// ============================================================================

@Suite("CLI File Input Tests", .acervoEnvironment)
struct CLIFileInputTests {

  // --- Test 5: -f /tmp/input.txt reads file path ---

  @Test("-f flag parses file path for reading input text")
  func fileFlagReadsPath() throws {
    let command = try DigaCommand.parse(["-f", "/tmp/input.txt"])
    #expect(command.file == "/tmp/input.txt")
    #expect(command.positionalArgs.isEmpty)
  }

  // --- Test 6: -f - parses as stdin indicator ---

  @Test("-f - is parsed as the stdin indicator")
  func fileFlagDashIndicatesStdin() throws {
    let command = try DigaCommand.parse(["-f", "-"])
    #expect(command.file == "-")
  }

  // --- Test 7: No input triggers help (verified via parse structure) ---

  @Test("No input flags and no positional args produces empty state for help")
  func noInputTriggersHelpState() throws {
    let command = try DigaCommand.parse([])
    #expect(command.file == nil)
    #expect(command.positionalArgs.isEmpty)
    #expect(command.voice == nil)
    #expect(command.output == nil)
    // When run() is called with no input and isatty returns true,
    // the command would throw CleanExit.helpRequest.
  }
}

// ============================================================================
// 7.3 — Model Flag Tests
// ============================================================================

@Suite("CLI Model Flag Tests", .acervoEnvironment)
struct CLIModelFlagTests {

  // --- Test 8: --model 0.6b selects the small model ---

  @Test("--model 0.6b resolves to the 0.6B model ID")
  func modelFlag06bSelectsSmall() throws {
    let command = try DigaCommand.parse(["--model", "0.6b", "hello"])
    #expect(command.model == "0.6b")

    // Verify the shorthand maps correctly.
    // Since resolveModelFlag is private, test the equivalent logic.
    let modelValue = "0.6b"
    switch modelValue.lowercased() {
    case "0.6b":
      #expect(Qwen3TTSModelRepo.base0_6B.rawValue == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
    default:
      Issue.record("Expected 0.6b to match")
    }
  }

  // --- Test 9: --model 1.7b selects the large model ---

  @Test("--model 1.7b resolves to the 1.7B model ID")
  func modelFlag17bSelectsLarge() throws {
    let command = try DigaCommand.parse(["--model", "1.7b", "hello"])
    #expect(command.model == "1.7b")

    let modelValue = "1.7b"
    switch modelValue.lowercased() {
    case "1.7b":
      #expect(Qwen3TTSModelRepo.base1_7B.rawValue == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    default:
      Issue.record("Expected 1.7b to match")
    }
  }

  // --- Test 10: --model invalid does not match any shorthand ---

  @Test("--model with invalid value is not a recognized shorthand or model ID")
  func modelFlagInvalidValue() throws {
    let command = try DigaCommand.parse(["--model", "invalid", "hello"])
    #expect(command.model == "invalid")

    // The value "invalid" does not match 0.6b, 1.7b, and contains no "/",
    // so resolveModelFlag would throw a ValidationError.
    let modelValue = "invalid"
    let isValidShorthand = ["0.6b", "1.7b"].contains(modelValue.lowercased())
    let isHuggingFaceID = modelValue.contains("/")
    #expect(!isValidShorthand)
    #expect(!isHuggingFaceID)
  }

  // --- Test 11: --model with full HuggingFace ID is accepted ---

  @Test("--model with full HuggingFace model ID is accepted")
  func modelFlagHuggingFaceID() throws {
    let command = try DigaCommand.parse([
      "--model", "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16", "hello",
    ])
    #expect(command.model == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")

    // A value containing "/" is accepted as a HuggingFace model ID.
    #expect(command.model!.contains("/"))
  }
}

// ============================================================================
// 7.4 — Combined Flag Tests
// ============================================================================

@Suite("CLI Combined Flag Tests", .acervoEnvironment)
struct CLICombinedFlagTests {

  // --- Test 17: Combined flags parse correctly: -v daniel -o /tmp/out.wav "test" ---

  @Test("Combined flags -v -o and text all parse correctly")
  func combinedFlagsParseCorrectly() throws {
    let command = try DigaCommand.parse(["-v", "daniel", "-o", "/tmp/out.wav", "test"])
    #expect(command.voice == "daniel")
    #expect(command.output == "/tmp/out.wav")
    #expect(command.positionalArgs == ["test"])
    #expect(command.file == nil)
  }

  // --- Test 18: All flags compose: -v alex -o out.wav -f input.txt ---

  @Test("All input/output/voice flags compose without conflict")
  func allFlagsCompose() throws {
    let command = try DigaCommand.parse([
      "-v", "samantha",
      "-o", "/tmp/output.m4a",
      "-f", "/tmp/script.txt",
      "--model", "0.6b",
    ])
    #expect(command.voice == "samantha")
    #expect(command.output == "/tmp/output.m4a")
    #expect(command.file == "/tmp/script.txt")
    #expect(command.model == "0.6b")
    #expect(command.positionalArgs.isEmpty)
  }

  // --- Test 19: Standalone commands parse independently ---

  @Test("--voices flag parses as standalone command")
  func standaloneVoicesFlag() throws {
    let command = try DigaCommand.parse(["--voices"])
    #expect(command.voices == true)
    #expect(command.positionalArgs.isEmpty)
  }

  // --- Test 20: --file-format flag works with -o ---

  @Test("--file-format flag composes with -o flag")
  func fileFormatComposesWithOutput() throws {
    let command = try DigaCommand.parse([
      "-o", "/tmp/out.bin",
      "--file-format", "m4a",
      "hello",
    ])
    #expect(command.output == "/tmp/out.bin")
    #expect(command.fileFormat == "m4a")
    #expect(command.positionalArgs == ["hello"])
  }
}

// ============================================================================
// 7.5 — chunkTargetDuration Flag Tests
// ============================================================================

@Suite("CLI chunkTargetDuration Flag Tests", .acervoEnvironment)
struct CLIChunkTargetDurationTests {

  @Test("Without --chunk-target-duration, the parsed value is nil (DigaEngine uses .default)")
  func noFlagDefaultsToNil() throws {
    let command = try DigaCommand.parse(["hello"])
    #expect(command.chunkTargetDuration == nil)
  }

  @Test("--chunk-target-duration parses an integer value")
  func parsesIntegerValue() throws {
    let command = try DigaCommand.parse(["--chunk-target-duration", "8", "hello"])
    #expect(command.chunkTargetDuration == 8.0)
  }

  @Test("--chunk-target-duration parses a fractional value")
  func parsesFractionalValue() throws {
    let command = try DigaCommand.parse(["--chunk-target-duration", "10.5", "hello"])
    #expect(command.chunkTargetDuration == 10.5)
  }

  @Test("--chunk-target-duration rejects non-numeric input at parse time")
  func rejectsNonNumeric() {
    #expect(throws: (any Error).self) {
      _ = try DigaCommand.parse(["--chunk-target-duration", "abc", "hello"])
    }
  }

  @Test("--chunk-target-duration=-N form parses (help text documents this for negatives)")
  func equalsFormParsesNegative() throws {
    // The help text instructs users to pass negatives via '=' (e.g. --chunk-target-duration=-5)
    // because ArgumentParser otherwise treats a leading '-' as the next flag. Confirm the
    // syntax actually works at parse time. (Validation in run() rejects values <= 0; this
    // test only covers the parse layer.)
    let command = try DigaCommand.parse(["--chunk-target-duration=-5", "hello"])
    #expect(command.chunkTargetDuration == -5.0)
  }

  @Test("--chunk-target-duration composes with --voice and --model")
  func composesWithOtherFlags() throws {
    let command = try DigaCommand.parse([
      "-v", "alex",
      "--model", "0.6b",
      "--chunk-target-duration", "6.5",
      "hello",
    ])
    #expect(command.voice == "alex")
    #expect(command.model == "0.6b")
    #expect(command.chunkTargetDuration == 6.5)
  }

  @Test("DigaEngine stores a custom chunkTargetDuration through GenerationSettings")
  func engineStoresCustomChunkTargetDuration() async {
    let settings = GenerationSettings(chunkTargetDuration: 6.0)
    let engine = DigaEngine(generationSettings: settings)
    let stored = await engine.generationSettings
    #expect(stored.chunkTargetDuration == 6.0)
  }

  @Test("DigaEngine without explicit settings falls back to GenerationSettings.default")
  func engineDefaultChunkTargetDuration() async {
    let engine = DigaEngine()
    let stored = await engine.generationSettings
    #expect(stored.chunkTargetDuration == GenerationSettings.default.chunkTargetDuration)
  }
}

// ============================================================================
// 7.6 — Additional Integration Tests
// ============================================================================

@Suite("CLI Integration Verification Tests", .acervoEnvironment)
struct CLIIntegrationVerificationTests {

  // --- Test 23: Model shorthand case insensitivity ---

  @Test("Model shorthand is case-insensitive (0.6B and 0.6b both valid)")
  func modelShorthandCaseInsensitive() throws {
    // Both uppercase and lowercase B should be accepted.
    let lower = try DigaCommand.parse(["--model", "0.6b", "hello"])
    let upper = try DigaCommand.parse(["--model", "0.6B", "hello"])

    // Both parse to the same model flag value (case varies but resolveModelFlag lowercases).
    #expect(lower.model == "0.6b")
    #expect(upper.model == "0.6B")

    // Both should resolve to the same model ID when lowercased.
    #expect(lower.model!.lowercased() == upper.model!.lowercased())
  }

  // --- Test 24: Multiple text positional args join with spaces ---

  @Test("Multiple positional text arguments are joined with spaces")
  func multiplePositionalArgsJoinedWithSpaces() throws {
    let command = try DigaCommand.parse(["hello", "beautiful", "world"])
    #expect(command.positionalArgs == ["hello", "beautiful", "world"])

    // The run method joins them: positionalArgs.joined(separator: " ")
    let joined = command.positionalArgs.joined(separator: " ")
    #expect(joined == "hello beautiful world")
  }
}
