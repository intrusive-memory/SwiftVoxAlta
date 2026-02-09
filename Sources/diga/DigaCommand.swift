import ArgumentParser
import Foundation

/// Minimum RAM in bytes required to run even the smallest (0.6B) TTS model.
/// Below this threshold, the CLI falls back to Apple TTS unconditionally.
/// 4 GB is a conservative minimum for a 0.6B parameter model with MLX overhead.
private let minimumRAMForTTS: UInt64 = 4 * 1024 * 1024 * 1024

@main
struct DigaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diga",
        abstract: "On-device neural text-to-speech — a drop-in replacement for /usr/bin/say.",
        version: "diga \(DigaVersion.current)"
    )

    // MARK: - Voice Management Flags

    @Flag(name: .long, help: "List all available voices and exit.")
    var voices: Bool = false

    @Option(name: .long, help: "Create a new voice from a text description: --design \"description\" <name>")
    var design: String?

    @Option(name: .long, help: "Clone a voice from a reference audio file: --clone reference.wav <name>")
    var clone: String?

    // MARK: - Model Management Flags

    @Option(name: .long, help: "Override the auto-selected TTS model (0.6b, 1.7b, or a HuggingFace model ID).")
    var model: String?

    // MARK: - Output Flags (Sprint 5 + Sprint 6)

    @Option(name: .shortAndLong, help: "Write audio to a file instead of playing through speakers.")
    var output: String?

    @Option(name: .shortAndLong, help: "Read input text from a file (use '-' for stdin).")
    var file: String?

    @Option(name: .long, help: "Override the output audio format (wav, aiff, m4a). Inferred from file extension if not set.")
    var fileFormat: String?

    // MARK: - Voice Selection (Sprint 5 + Sprint 7)

    @Option(name: .shortAndLong, help: "Voice name to use for synthesis. Use '-v ?' to list voices.")
    var voice: String?

    // MARK: - Positional Arguments

    @Argument(help: "Voice name (used with --design or --clone), or text to speak.")
    var positionalArgs: [String] = []

    // MARK: - Run

    mutating func run() async throws {
        // Sprint 7: -v ? lists voices and exits.
        if voice == "?" {
            try runListVoices()
            return
        }

        if voices {
            try runListVoices()
            return
        }

        if let description = design {
            try runDesignVoice(description: description)
            return
        }

        if let referencePath = clone {
            try runCloneVoice(referencePath: referencePath)
            return
        }

        // Sprint 7: Resolve --model shorthand (0.6b, 1.7b) to full HuggingFace IDs.
        let resolvedModel = try resolveModelFlag()

        // Sprint 7: Validate voice name before doing anything expensive.
        if let voiceName = voice {
            try validateVoiceExists(name: voiceName)
        }

        // Sprint 7: Determine input text from one of three sources:
        // 1. -f flag: read from file (or stdin if "-")
        // 2. Positional arguments: join as text
        // 3. Stdin (when piped, i.e., stdin is not a TTY)
        let text: String
        if let filePath = file {
            if filePath == "-" {
                // Sprint 7: -f - reads from stdin
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

        // Sprint 7: Check if we need to fall back to Apple TTS.
        let shouldFallback = try await shouldUseFallback(resolvedModel: resolvedModel)
        if shouldFallback {
            try executeFallback(text: trimmedText)
            return
        }

        // Synthesize text to WAV audio.
        let engine = DigaEngine(modelOverride: resolvedModel)
        let wavData = try await engine.synthesize(text: trimmedText, voiceName: voice)

        // Route output: file (-o) or speaker playback.
        if let outputPath = output {
            // Sprint 6: Infer format from extension or --file-format flag, then write.
            let format = AudioFormat.infer(fromPath: outputPath, formatOverride: fileFormat)
            try AudioFileWriter.write(wavData: wavData, to: outputPath, format: format)
            // Silent on success — matches `say -o` behavior.
        } else {
            // Play through speakers (default behavior, Sprint 5).
            try await AudioPlayback.play(wavData: wavData)
        }
    }

    // MARK: - Model Flag Resolution (Sprint 7)

    /// Resolves the `--model` flag to a full HuggingFace model ID.
    ///
    /// Shorthand values:
    /// - `"0.6b"` or `"0.6B"` → `TTSModelID.small`
    /// - `"1.7b"` or `"1.7B"` → `TTSModelID.large`
    /// - Any other string is treated as a custom HuggingFace model ID
    /// - `nil` returns `nil` (use auto-selection)
    ///
    /// - Returns: The resolved model ID, or nil for auto-selection.
    /// - Throws: `ValidationError` if the model value is invalid.
    private func resolveModelFlag() throws -> String? {
        guard let modelValue = model else { return nil }

        switch modelValue.lowercased() {
        case "0.6b":
            return TTSModelID.small
        case "1.7b":
            return TTSModelID.large
        default:
            // Accept any string that looks like a HuggingFace model ID (contains /).
            // Also accept full model IDs like "mlx-community/Qwen3-TTS-12Hz-1.7B".
            if modelValue.contains("/") {
                return modelValue
            }
            // Invalid shorthand — not "0.6b", "1.7b", or a HF model ID.
            throw ValidationError(
                "Invalid model: '\(modelValue)'. Use '0.6b', '1.7b', or a HuggingFace model ID (org/repo)."
            )
        }
    }

    // MARK: - Voice Validation (Sprint 7)

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
        if let _ = try store.getVoice(name: name) {
            return
        }

        // Voice not found — print error to stderr and exit with code 1.
        let message = "Error: Voice '\(name)' not found. Use --voices to list available voices.\n"
        FileHandle.standardError.write(Data(message.utf8))
        throw ExitCode.failure
    }

    // MARK: - Apple TTS Fallback (Sprint 7)

    /// Determines whether the CLI should fall back to Apple TTS.
    ///
    /// Fallback conditions:
    /// 1. Machine has insufficient RAM for the smallest TTS model
    /// 2. The required model is not available and download fails
    ///
    /// - Parameter resolvedModel: The resolved model ID, or nil for auto-selection.
    /// - Returns: `true` if Apple TTS should be used instead.
    private func shouldUseFallback(resolvedModel: String?) async throws -> Bool {
        // Check RAM minimum — if the machine can't even run 0.6B, fall back.
        let ram = ProcessInfo.processInfo.physicalMemory
        if ram < minimumRAMForTTS {
            return true
        }

        // Determine which model to check.
        let manager = DigaModelManager()
        let modelId = resolvedModel ?? manager.recommendedModel()

        // Check if model is already available.
        let available = await manager.isModelAvailable(modelId)
        if available {
            return false
        }

        // Model not available — attempt download.
        do {
            let notice = "Model \(modelId) not found locally. Downloading...\n"
            FileHandle.standardError.write(Data(notice.utf8))

            try await manager.downloadModel(modelId) { bytesDownloaded, totalBytes, fileName in
                DigaModelManager.printProgress(
                    bytesDownloaded: bytesDownloaded,
                    totalBytes: totalBytes,
                    fileName: fileName
                )
            }

            let done = "Model download complete.\n"
            FileHandle.standardError.write(Data(done.utf8))
            return false
        } catch {
            // Download failed — fall back to Apple TTS.
            return true
        }
    }

    /// Execute the Apple TTS fallback with mapped flags.
    ///
    /// - Parameter text: The text to speak (already trimmed).
    /// - Throws: `SayFallbackError` if say fails.
    private func executeFallback(text: String) throws {
        // Map -f flag: if -f was used, pass the original path to say.
        // For -f -, we already read stdin into text, so pass text directly.
        let sayFilePath: String?
        if let filePath = file, filePath != "-" {
            sayFilePath = filePath
        } else {
            sayFilePath = nil
        }

        // Only pass text if we don't have a file path.
        let sayText = sayFilePath == nil ? text : nil

        try SayFallback.execute(
            voice: voice,
            outputPath: output,
            filePath: sayFilePath,
            text: sayText
        )
    }

    // MARK: - Input Reading (Sprint 5 + Sprint 7)

    /// Read text from a file path.
    ///
    /// - Parameter path: Path to the input text file.
    /// - Returns: The file contents as a string.
    /// - Throws: `ValidationError` if the file cannot be read.
    private func readInputFile(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ValidationError("Input file not found or not readable: \(path)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Read all text from standard input until EOF.
    ///
    /// - Returns: The stdin contents as a string.
    /// - Throws: `ValidationError` if stdin cannot be read.
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
            print("  (none \u{2014} use --design or --clone to create)")
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
                }
                print("  \(voice.name)\t\(description)")
            }
        }
    }

    // MARK: - --design

    /// Creates a new voice from a text description and saves it to the VoiceStore.
    private func runDesignVoice(description: String) throws {
        guard let voiceName = positionalArgs.first else {
            throw ValidationError("A voice name is required: --design \"description\" <name>")
        }

        let voice = StoredVoice(
            name: voiceName,
            type: .designed,
            designDescription: description,
            clonePromptPath: nil,
            createdAt: Date()
        )

        let store = VoiceStore()
        try store.saveVoice(voice)
        print("Voice \"\(voiceName)\" created.")
    }

    // MARK: - --clone

    /// Clones a voice from a reference audio file and saves it to the VoiceStore.
    private func runCloneVoice(referencePath: String) throws {
        guard let voiceName = positionalArgs.first else {
            throw ValidationError("A voice name is required: --clone reference.wav <name>")
        }

        // Validate the reference audio file exists and is readable.
        let fileURL = URL(fileURLWithPath: referencePath)
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw ValidationError("Reference audio file not found or not readable: \(referencePath)")
        }

        let voice = StoredVoice(
            name: voiceName,
            type: .cloned,
            designDescription: nil,
            clonePromptPath: referencePath,
            createdAt: Date()
        )

        let store = VoiceStore()
        try store.saveVoice(voice)

        let filename = fileURL.lastPathComponent
        print("Voice \"\(voiceName)\" cloned from \(filename)")
    }
}

// MARK: - Int32 Bool Extension (Sprint 5)

private extension Int32 {
    /// Converts a C-style boolean (0 = false, non-zero = true) to Swift Bool.
    var boolValue: Bool { self != 0 }
}
