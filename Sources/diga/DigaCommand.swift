import ArgumentParser
import Foundation

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

    @Option(name: .long, help: "Override the auto-selected TTS model (HuggingFace model ID).")
    var model: String?

    // MARK: - Output Flags (Sprint 5 + Sprint 6)

    @Option(name: .shortAndLong, help: "Write audio to a file instead of playing through speakers.")
    var output: String?

    @Option(name: .shortAndLong, help: "Read input text from a file.")
    var file: String?

    @Option(name: .long, help: "Override the output audio format (wav, aiff, m4a). Inferred from file extension if not set.")
    var fileFormat: String?

    // MARK: - Voice Selection (Sprint 5)

    @Option(name: .shortAndLong, help: "Voice name to use for synthesis.")
    var voice: String?

    // MARK: - Positional Arguments

    @Argument(help: "Voice name (used with --design or --clone), or text to speak.")
    var positionalArgs: [String] = []

    // MARK: - Run

    mutating func run() async throws {
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

        // Ensure model is available before proceeding with synthesis.
        try await ensureModelAvailable()

        // Determine input text from one of three sources:
        // 1. -f flag: read from file
        // 2. Positional arguments: join as text
        // 3. Stdin (when piped, i.e., stdin is not a TTY)
        let text: String
        if let filePath = file {
            text = try readInputFile(path: filePath)
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

        // Synthesize text to WAV audio.
        let engine = DigaEngine(modelOverride: model)
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

    // MARK: - Model Management

    /// Ensures the appropriate TTS model is downloaded and available.
    ///
    /// If a `--model` flag is provided, that model is used. Otherwise,
    /// the system RAM is queried and the recommended model is selected.
    /// If the model is not already cached, it is downloaded with a progress bar.
    private func ensureModelAvailable() async throws {
        let manager = DigaModelManager()

        // Determine which model to use
        let modelId: String
        if let override = model {
            modelId = override
        } else {
            modelId = manager.recommendedModel()
        }

        // Check if already downloaded
        let available = await manager.isModelAvailable(modelId)
        if available {
            return
        }

        // Print download notice to stderr
        let notice = "Model \(modelId) not found locally. Downloading...\n"
        FileHandle.standardError.write(Data(notice.utf8))

        // Download with progress reporting to stderr
        try await manager.downloadModel(modelId) { bytesDownloaded, totalBytes, fileName in
            DigaModelManager.printProgress(
                bytesDownloaded: bytesDownloaded,
                totalBytes: totalBytes,
                fileName: fileName
            )
        }

        let done = "Model download complete.\n"
        FileHandle.standardError.write(Data(done.utf8))
    }

    // MARK: - Input Reading (Sprint 5)

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
