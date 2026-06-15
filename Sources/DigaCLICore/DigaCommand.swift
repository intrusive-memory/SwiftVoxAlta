import ArgumentParser
import Foundation
import SwiftVoxAlta

// `@available` is required here because the executable enters this async root
// command via top-level `await DigaCommand.main()` in `Sources/diga/main.swift`
// instead of the `@main` macro. The `@main` macro would otherwise synthesize
// this annotation onto the synthesized entry point; calling `.main()` directly
// loses that, so ArgumentParser's async runtime entry point needs the command
// itself to declare an availability floor. See TODO-cli-bundling.md.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct DigaCommand: AsyncParsableCommand {
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "diga",
    abstract: "On-device neural text-to-speech — a drop-in replacement for /usr/bin/say.",
    version: "diga \(DigaVersion.current)"
  )

  // MARK: - Voice Management Flags

  @Flag(name: .long, help: "List all available voices and exit.")
  public var voices: Bool = false

  @Option(name: .long, help: "Import a voice from a .vox file: --import-vox voice.vox")
  public var importVox: String?

  @Option(
    name: [.customShort("l"), .long],
    help:
      "BCP-47 language tag (e.g. es-MX, fr-FR) selecting which language-keyed embedding to import from a multi-language .vox. Resolution falls back exact → base-language → default. Default: the .vox default embedding."
  )
  public var language: String?

  // MARK: - Model Management Flags

  @Option(
    name: .long,
    help: "Override the auto-selected TTS model (0.6b, 1.7b, or a HuggingFace model ID).")
  public var model: String?

  // MARK: - Output Flags

  @Option(name: .shortAndLong, help: "Write audio to a file instead of playing through speakers.")
  public var output: String?

  @Option(name: .shortAndLong, help: "Read input text from a file (use '-' for stdin).")
  public var file: String?

  @Option(
    name: .long,
    help:
      "Override the output audio format (wav, aiff, m4a). Inferred from file extension if not set.")
  public var fileFormat: String?

  // MARK: - Voice Selection

  @Option(name: .shortAndLong, help: "Voice name to use for synthesis. Use '-v ?' to list voices.")
  public var voice: String?

  @Option(
    name: .long,
    help: "Performance direction (e.g., 'speak softly', 'whisper'). Applied to all chunks.")
  public var instruct: String?

  // MARK: - Generation Settings

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Target maximum duration (seconds) per TTS chunk. Long inputs are split at sentence boundaries into chunks no longer than this; shorter values produce stronger prosody anchors but more inter-chunk pauses. Must be > 0. To pass a value that begins with '-' (e.g. an explicit negative), use the '=' form: --chunk-target-duration=-5. Default: \(GenerationSettings.default.chunkTargetDuration)s if not set."
    )
  )
  public var chunkTargetDuration: TimeInterval?

  // MARK: - Positional Arguments

  @Argument(help: "Text to speak.")
  public var positionalArgs: [String] = []

  // MARK: - Run

  public mutating func run() async throws {
    // -v ? lists voices and exits.
    if voice == "?" {
      try runListVoices()
      return
    }

    if voices {
      try runListVoices()
      return
    }

    if let voxPath = importVox {
      try runImportVox(path: voxPath)
      return
    }

    // Resolve --model shorthand (0.6b, 1.7b) to full HuggingFace IDs.
    let resolvedModel = try resolveModelFlag()

    // Check if -v points to a .vox file for direct synthesis.
    let isVoxFile =
      voice?.hasSuffix(".vox") == true
      && FileManager.default.isReadableFile(atPath: voice!)

    // Validate voice name before doing anything expensive.
    if let voiceName = voice, !isVoxFile {
      try validateVoiceExists(name: voiceName)
    }

    // Determine input text from one of three sources:
    // 1. -f flag: read from file (or stdin if "-")
    // 2. Positional arguments: join as text
    // 3. Stdin (when piped, i.e., stdin is not a TTY)
    let text: String
    if let filePath = file {
      if filePath == "-" {
        text = try readStdin()
      } else {
        text = try readInputFile(path: filePath)
      }
    } else if !positionalArgs.isEmpty {
      text = positionalArgs.joined(separator: " ")
    } else if !isatty(STDIN_FILENO).boolValue {
      text = try readStdin()
    } else {
      // No input provided — print help.
      throw CleanExit.helpRequest(self)
    }

    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      throw ValidationError("Input text is empty.")
    }

    if let duration = chunkTargetDuration, duration <= 0 {
      throw ValidationError("--chunk-target-duration must be greater than 0.")
    }

    // Synthesize text to WAV audio via Qwen3-TTS.
    let generationSettings: GenerationSettings
    if let duration = chunkTargetDuration {
      generationSettings = GenerationSettings(chunkTargetDuration: duration)
    } else {
      generationSettings = .default
    }
    let engine = DigaEngine(
      modelOverride: resolvedModel,
      generationSettings: generationSettings
    )
    let wavData: Data
    if isVoxFile {
      wavData = try await engine.synthesizeFromVox(
        text: trimmedText, voxPath: voice!, instruct: instruct)
    } else {
      wavData = try await engine.synthesize(text: trimmedText, voiceName: voice, instruct: instruct)
    }

    // Route output: file (-o) or speaker playback.
    if let outputPath = output {
      // Infer format from extension or --file-format flag, then write.
      let format = AudioFormat.infer(fromPath: outputPath, formatOverride: fileFormat)
      try AudioFileWriter.write(wavData: wavData, to: outputPath, format: format)
      // Silent on success — matches `say -o` behavior.
    } else {
      // Play through speakers (default behavior).
      try await AudioPlayback.play(wavData: wavData)
    }
  }

  // MARK: - Model Flag Resolution

  /// Resolves the `--model` flag to a full HuggingFace model ID.
  ///
  /// Shorthand values:
  /// - `"0.6b"` or `"0.6B"` → `Qwen3TTSModelRepo.base0_6B.rawValue`
  /// - `"1.7b"` or `"1.7B"` → `Qwen3TTSModelRepo.base1_7B.rawValue`
  /// - Any other string containing `/` is treated as a HuggingFace model ID
  /// - `nil` returns `nil` (use auto-selection)
  ///
  /// - Returns: The resolved model ID, or nil for auto-selection.
  /// - Throws: `ValidationError` if the model value is invalid.
  private func resolveModelFlag() throws -> String? {
    guard let modelValue = model else { return nil }

    if let repo = Qwen3TTSModelRepo(slug: modelValue) {
      return repo.rawValue
    } else if modelValue.contains("/") {
      // Accept any string that looks like a HuggingFace model ID.
      return modelValue
    } else {
      let slugs = Qwen3TTSModelRepo.supportedSlugs.sorted().joined(separator: "', '")
      throw ValidationError(
        "Invalid model: '\(modelValue)'. Use '\(slugs)', or a HuggingFace model ID (org/repo)."
      )
    }
  }

  /// Resolves the `--model` flag to a `.vox` model-size slug (`"0.6b"` / `"1.7b"`)
  /// for import queries, or `nil` when no `--model` was given (→ import every
  /// supported size present in the archive).
  ///
  /// Accepts a bare size slug or a known HuggingFace model ID. An unrecognized
  /// HuggingFace ID (one not in `Qwen3TTSModelRepo`) has no `.vox` size mapping,
  /// so it resolves to `nil` (import all). A non-slug, non-`/` value is rejected.
  private func resolveImportModelSlug() throws -> String? {
    guard let modelValue = model else { return nil }
    if let repo = Qwen3TTSModelRepo(slug: modelValue) { return repo.slug }
    if let repo = Qwen3TTSModelRepo(rawValue: modelValue) { return repo.slug }
    if modelValue.contains("/") { return nil }
    let slugs = Qwen3TTSModelRepo.supportedSlugs.sorted().joined(separator: "', '")
    throw ValidationError(
      "Invalid model: '\(modelValue)'. Use '\(slugs)', or a HuggingFace model ID (org/repo)."
    )
  }

  // MARK: - Voice Validation

  /// Validates that a voice name exists in built-in voices or the VoiceStore.
  ///
  /// - Parameter name: The voice name to validate.
  /// - Throws: `ExitCode.failure` if the voice is not found.
  private func validateVoiceExists(name: String) throws {
    // Check built-in voices.
    if BuiltinVoices.get(name: name) != nil {
      return
    }

    // Check custom voices in VoiceStore.
    let store = VoiceStore()
    if (try store.getVoice(name: name)) != nil {
      return
    }

    // Voice not found — print error to stderr and exit with code 1.
    let message = "Error: Voice '\(name)' not found. Use --voices to list available voices.\n"
    FileHandle.standardError.write(Data(message.utf8))
    throw ExitCode.failure
  }

  // MARK: - Input Reading

  /// Read text from a file path.
  private func readInputFile(path: String) throws -> String {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      throw ValidationError("Input file not found or not readable: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// Read all text from standard input until EOF.
  private func readStdin() throws -> String {
    var lines: [String] = []
    while let line = readLine(strippingNewline: false) {
      lines.append(line)
    }
    return lines.joined()
  }

  // MARK: - --voices

  /// Prints a formatted list of built-in and custom voices.
  private func runListVoices() throws {
    let builtinVoices = BuiltinVoices.all()

    print("Built-in:")
    for voice in builtinVoices {
      let description = voice.designDescription ?? ""
      print("  \(voice.name)\t\(description)")
    }

    print("")
    print("Custom:")

    let store = VoiceStore()
    let customVoices = try store.listVoices().filter { $0.type != .builtin }

    if customVoices.isEmpty {
      print("  (none \u{2014} use `echada cast` to create, then --import-vox)")
    } else {
      for voice in customVoices {
        let description: String
        switch voice.type {
        case .designed:
          description = voice.designDescription ?? "(designed)"
        case .cloned:
          description = "cloned from \(voice.clonePromptPath ?? "reference audio")"
        case .builtin:
          description = voice.designDescription ?? ""
        case .preset:
          description = "preset speaker: \(voice.clonePromptPath ?? "unknown")"
        }
        print("  \(voice.name)\t\(description)")
      }
    }
  }

  // MARK: - --import-vox

  /// Imports a voice from a .vox file and registers it in the VoiceStore.
  private func runImportVox(path: String) throws {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
      throw ValidationError("VOX file not found or not readable: \(path)")
    }

    // Determine which model sizes to import clone prompts for. An explicit --model
    // narrows to that single size; otherwise import every supported size the .vox
    // carries, so the voice works regardless of which model synthesizes it.
    let requestedSlug = try resolveImportModelSlug()
    let slugsToImport = requestedSlug.map { [$0] } ?? Qwen3TTSModelRepo.supportedSlugs.sorted()
    let primarySlug = requestedSlug ?? Qwen3TTSModelRepo.base1_7B.slug

    // Primary import drives metadata, voice type, and language discovery.
    let result = try VoxImporter.importVox(
      from: fileURL, modelQuery: primarySlug, language: language)
    if let language, !language.isEmpty {
      let available = result.availableLanguages
      let availableNote = available.isEmpty ? "default only" : available.joined(separator: ", ")
      print("Selecting language '\(language)' (available: \(availableNote)).")
    }

    // Collect clone-prompt data per requested size, re-querying the archive for any
    // non-primary sizes. Sizes the .vox doesn't carry are simply skipped.
    var clonePromptBySlug: [String: Data] = [:]
    for slug in slugsToImport {
      let sized =
        slug == primarySlug
        ? result
        : try VoxImporter.importVox(from: fileURL, modelQuery: slug, language: language)
      if let data = sized.clonePromptData {
        clonePromptBySlug[slug] = data
      }
    }

    let store = VoiceStore()

    // Determine voice type from provenance method.
    let voiceType: VoiceType
    switch result.method {
    case "cloned":
      voiceType = .cloned
    case "preset":
      voiceType = .preset
    case "synthesized":
      voiceType = .designed
    default:
      voiceType = .designed
    }

    // Write clone prompts to disk for each imported size.
    var clonePromptPath: String?
    if !clonePromptBySlug.isEmpty {
      try FileManager.default.createDirectory(
        at: store.voicesDirectory,
        withIntermediateDirectories: true
      )

      // Clear stale model-specific clone prompt caches before writing fresh data.
      for slug in Qwen3TTSModelRepo.supportedSlugs.sorted() {
        let staleURL = store.voicesDirectory.appendingPathComponent(
          "\(result.name)-\(slug).cloneprompt")
        try? FileManager.default.removeItem(at: staleURL)
      }

      // Write each imported size to its model-specific path.
      for (slug, data) in clonePromptBySlug.sorted(by: { $0.key < $1.key }) {
        let modelURL = store.voicesDirectory.appendingPathComponent(
          "\(result.name)-\(slug).cloneprompt")
        try data.write(to: modelURL, options: .atomic)
      }

      // The legacy unsuffixed cache is treated as 1.7B-only by the engine; mirror
      // the 1.7b data there for backward compatibility when it was imported.
      if let data17 = clonePromptBySlug[Qwen3TTSModelRepo.base1_7B.slug] {
        let legacyURL = store.voicesDirectory.appendingPathComponent("\(result.name).cloneprompt")
        try data17.write(to: legacyURL, options: .atomic)
      }
    }

    // For cloned voices without a clone prompt, store reference audio path.
    if voiceType == .cloned && clonePromptBySlug.isEmpty {
      // Write first reference audio to disk for later clone prompt extraction.
      if let (filename, data) = result.referenceAudio.first {
        let refPath = store.voicesDirectory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(
          at: store.voicesDirectory,
          withIntermediateDirectories: true
        )
        try data.write(to: refPath, options: .atomic)
        clonePromptPath = refPath.path
      }
    }

    // Copy the .vox file to the voices directory.
    let destVoxURL = store.voicesDirectory.appendingPathComponent("\(result.name).vox")
    try FileManager.default.createDirectory(
      at: store.voicesDirectory,
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: destVoxURL.path) {
      try FileManager.default.removeItem(at: destVoxURL)
    }
    try FileManager.default.copyItem(at: fileURL, to: destVoxURL)

    let voice = StoredVoice(
      name: result.name,
      type: voiceType,
      designDescription: result.description,
      clonePromptPath: clonePromptPath,
      createdAt: result.createdAt
    )
    try store.saveVoice(voice)

    if !clonePromptBySlug.isEmpty {
      let sizes = clonePromptBySlug.keys.sorted().joined(separator: ", ")
      print("Voice \"\(result.name)\" imported (ready to use; models: \(sizes)).")
    } else {
      print("Voice \"\(result.name)\" imported (clone prompt will generate on first use).")
    }
  }

  // MARK: - Async Entry Point

  /// Parses command-line arguments and runs the command asynchronously, then
  /// exits — the library-side equivalent of `@main`.
  ///
  /// The thin `diga` executable (`Sources/diga/main.swift`) calls this from
  /// top-level `await`. It exists because the *async* `AsyncParsableCommand`
  /// overloads of `main()` / `main(_:)` are gated behind
  /// `@available(macOS 10.15, …)`. Top-level code in a `main.swift` is not an
  /// availability-annotated scope, so a bare `await DigaCommand.main()` there
  /// resolves to the *synchronous* `ParsableCommand.main()` overload, which
  /// detects the async root at runtime and aborts with "Asynchronous root
  /// command needs availability annotation." Routing through this annotated
  /// method puts the call in an availability-satisfied context so the async
  /// overload is selected. See TODO-cli-bundling.md.
  public static func runAsMain() async {
    await Self.main(nil)
  }
}

// MARK: - Int32 Bool Extension

extension Int32 {
  /// Converts a C-style boolean (0 = false, non-zero = true) to Swift Bool.
  fileprivate var boolValue: Bool { self != 0 }
}
