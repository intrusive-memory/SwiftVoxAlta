import ArgumentParser
import Foundation
import SwiftVoxAlta

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

    @Option(name: .long, help: "Import a voice from a .vox file: --import-vox voice.vox")
    var importVox: String?

    // MARK: - Model Management Flags

    @Option(name: .long, help: "Override the auto-selected TTS model (0.6b, 1.7b, or a HuggingFace model ID).")
    var model: String?

    // MARK: - Output Flags

    @Option(name: .shortAndLong, help: "Write audio to a file instead of playing through speakers.")
    var output: String?

    @Option(name: .shortAndLong, help: "Read input text from a file (use '-' for stdin).")
    var file: String?

    @Option(name: .long, help: "Override the output audio format (wav, aiff, m4a). Inferred from file extension if not set.")
    var fileFormat: String?

    // MARK: - Voice Selection

    @Option(name: .shortAndLong, help: "Voice name to use for synthesis. Use '-v ?' to list voices.")
    var voice: String?

    @Option(name: .long, help: "Performance direction (e.g., 'speak softly', 'whisper'). Applied to all chunks.")
    var instruct: String?

    // MARK: - Positional Arguments

    @Argument(help: "Text to speak.")
    var positionalArgs: [String] = []

    // MARK: - Run

    mutating func run() async throws {
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
        let isVoxFile = voice?.hasSuffix(".vox") == true
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

        // Synthesize text to WAV audio via Qwen3-TTS.
        let engine = DigaEngine(modelOverride: resolvedModel)
        let wavData: Data
        if isVoxFile {
            wavData = try await engine.synthesizeFromVox(text: trimmedText, voxPath: voice!, instruct: instruct)
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
        if let _ = try store.getVoice(name: name) {
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

        let result = try VoxImporter.importVox(from: fileURL)
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

        // Write clone prompt to disk if present.
        var clonePromptPath: String?
        if let promptData = result.clonePromptData {
            try FileManager.default.createDirectory(
                at: store.voicesDirectory,
                withIntermediateDirectories: true
            )

            // Clear stale model-specific clone prompt caches before writing fresh data.
            for slug in Qwen3TTSModelRepo.supportedSlugs.sorted() {
                let staleURL = store.voicesDirectory.appendingPathComponent("\(result.name)-\(slug).cloneprompt")
                try? FileManager.default.removeItem(at: staleURL)
            }

            // Write to both legacy (unsuffixed) and default model-specific paths.
            let legacyURL = store.voicesDirectory.appendingPathComponent("\(result.name).cloneprompt")
            try promptData.write(to: legacyURL, options: .atomic)

            let modelURL = store.voicesDirectory.appendingPathComponent("\(result.name)-1.7b.cloneprompt")
            try promptData.write(to: modelURL, options: .atomic)
        }

        // For cloned voices without a clone prompt, store reference audio path.
        if voiceType == .cloned && result.clonePromptData == nil {
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

        if result.clonePromptData != nil {
            print("Voice \"\(result.name)\" imported (ready to use).")
        } else {
            print("Voice \"\(result.name)\" imported (clone prompt will generate on first use).")
        }
    }
}

// MARK: - Int32 Bool Extension

private extension Int32 {
    /// Converts a C-style boolean (0 = false, non-zero = true) to Swift Bool.
    var boolValue: Bool { self != 0 }
}
