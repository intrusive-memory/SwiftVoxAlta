import Foundation

// MARK: - SayFallbackError

/// Errors produced by the Apple TTS fallback system.
enum SayFallbackError: Error, LocalizedError, Sendable {
    /// The `/usr/bin/say` binary was not found on the system.
    case sayNotFound

    /// The `/usr/bin/say` process exited with a non-zero status.
    case sayFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .sayNotFound:
            return "Apple TTS fallback failed: /usr/bin/say not found."
        case .sayFailed(let exitCode, let stderr):
            let detail = stderr.isEmpty ? "exit code \(exitCode)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Apple TTS failed: \(detail)"
        }
    }
}

// MARK: - SayFallback

/// Maps diga CLI flags to `/usr/bin/say` arguments and executes Apple TTS as a fallback
/// when neural models are unavailable.
///
/// This fallback is triggered when:
/// - The required TTS model is not downloaded and download fails (no network, disk full)
/// - The machine has insufficient RAM for even the smallest (0.6B) model
///
/// Flag mapping:
/// - `-v voice` maps to `say -v voice`
/// - `-o output` maps to `say -o output`
/// - `-f file` maps to `say -f file`
/// - Bare text arguments pass through unchanged
enum SayFallback: Sendable {

    /// The path to Apple's built-in `say` command.
    static let sayPath = "/usr/bin/say"

    /// The stderr notice printed when falling back to Apple TTS.
    static let fallbackNotice = "Using Apple TTS (run diga again with network to download neural model)"

    // MARK: - Flag Mapping

    /// Build the argument array for `/usr/bin/say` from diga flags.
    ///
    /// - Parameters:
    ///   - voice: The voice name (from `-v` flag), or nil.
    ///   - outputPath: The output file path (from `-o` flag), or nil.
    ///   - filePath: The input file path (from `-f` flag), or nil.
    ///   - text: Bare text to speak, or nil if input comes from a file/stdin.
    /// - Returns: An array of arguments suitable for `Process.arguments`.
    static func buildSayArguments(
        voice: String?,
        outputPath: String?,
        filePath: String?,
        text: String?
    ) -> [String] {
        var args: [String] = []

        if let voice = voice {
            args.append(contentsOf: ["-v", voice])
        }

        if let outputPath = outputPath {
            args.append(contentsOf: ["-o", outputPath])
        }

        if let filePath = filePath {
            args.append(contentsOf: ["-f", filePath])
        }

        if let text = text, filePath == nil {
            args.append(text)
        }

        return args
    }

    // MARK: - Execution

    /// Execute `/usr/bin/say` with the mapped arguments.
    ///
    /// Prints a fallback notice to stderr before invoking `say`.
    ///
    /// - Parameters:
    ///   - voice: The voice name (from `-v` flag), or nil.
    ///   - outputPath: The output file path (from `-o` flag), or nil.
    ///   - filePath: The input file path (from `-f` flag), or nil.
    ///   - text: Bare text to speak, or nil if input comes from a file/stdin.
    ///   - stdinData: Data to pipe to say's stdin (for `-f -` or piped input), or nil.
    /// - Throws: `SayFallbackError` if say is not found or exits with an error.
    static func execute(
        voice: String?,
        outputPath: String?,
        filePath: String?,
        text: String?,
        stdinData: Data? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: sayPath) else {
            throw SayFallbackError.sayNotFound
        }

        // Print fallback notice to stderr.
        let notice = "\(fallbackNotice)\n"
        FileHandle.standardError.write(Data(notice.utf8))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sayPath)
        process.arguments = buildSayArguments(
            voice: voice,
            outputPath: outputPath,
            filePath: filePath,
            text: text
        )

        // Capture stderr from say for error reporting.
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        // If we have stdin data to pipe (for stdin-sourced input), set it up.
        if let stdinData = stdinData {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            stdinPipe.fileHandleForWriting.write(stdinData)
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        process.waitUntilExit()

        let status = process.terminationStatus
        if status != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw SayFallbackError.sayFailed(exitCode: status, stderr: stderrString)
        }
    }
}
