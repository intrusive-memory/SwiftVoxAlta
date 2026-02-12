import Foundation
import AVFoundation

/// Generates reference audio files for voice cloning using macOS `say` command.
///
/// Used as a fallback when VoiceDesign is unavailable or too slow. Generates
/// short audio samples using Apple's built-in TTS voices, which can then be
/// used with Qwen3-TTS Base model for voice cloning.
enum ReferenceAudioGenerator {

    /// Voice mappings from our voice names to macOS `say` voices
    private static let sayVoiceMap: [String: String] = [
        "alex": "Alex",           // Male, American
        "samantha": "Samantha",   // Female, American
        "daniel": "Daniel",       // Male, British
        "karen": "Karen",         // Female, Australian
    ]

    /// Sample text to use for reference audio generation.
    /// Should be short but include varied phonemes.
    private static let referenceText = "Hello, this is a test of my voice."

    /// Generate reference audio for a voice using macOS `say` command.
    ///
    /// - Parameters:
    ///   - voiceName: The voice name (e.g., "alex", "samantha")
    ///   - outputPath: File path where the audio should be saved (.wav or .aiff)
    /// - Throws: `ReferenceAudioError` if generation fails
    static func generate(voiceName: String, outputPath: URL) throws {
        guard let sayVoice = sayVoiceMap[voiceName] else {
            throw ReferenceAudioError.voiceNotFound(
                "No macOS voice mapping for '\(voiceName)'"
            )
        }

        // Create parent directory if needed
        let parentDir = outputPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        }

        // Use `say` to generate reference audio
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [
            "-v", sayVoice,
            "-o", outputPath.path,
            "--file-format=WAVE",  // WAV format for compatibility
            "--data-format=LEI16@24000",  // 16-bit PCM, 24kHz (matches Qwen3-TTS)
            referenceText
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ReferenceAudioError.generationFailed(
                "say command failed for voice '\(sayVoice)': \(errorMessage)"
            )
        }

        // Verify the file was created and has reasonable size
        guard FileManager.default.fileExists(atPath: outputPath.path) else {
            throw ReferenceAudioError.generationFailed(
                "Reference audio file not created at \(outputPath.path)"
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputPath.path)
        guard let fileSize = attributes[.size] as? Int, fileSize > 1000 else {
            throw ReferenceAudioError.generationFailed(
                "Reference audio file is too small (\(attributes[.size] ?? 0) bytes)"
            )
        }
    }

    /// Check if reference audio exists for a voice
    static func exists(voiceName: String, in directory: URL) -> Bool {
        let refPath = directory.appendingPathComponent("\(voiceName)-reference.wav")
        return FileManager.default.fileExists(atPath: refPath.path)
    }

    /// Get the path where reference audio should be stored
    static func referencePath(voiceName: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(voiceName)-reference.wav")
    }
}

// MARK: - Error Types

enum ReferenceAudioError: Error, LocalizedError {
    case voiceNotFound(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .voiceNotFound(let detail): return "Voice not found: \(detail)"
        case .generationFailed(let detail): return "Reference audio generation failed: \(detail)"
        }
    }
}
