import Foundation
import SwiftAcervo

/// Known TTS model identifiers from HuggingFace.
enum TTSModelID {
    /// Large model (1.7B parameters) — better quality, requires 16GB+ RAM.
    static let large = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    /// Small model (0.6B parameters) — fits in less RAM.
    static let small = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    /// VoiceDesign model (1.7B only) — generates voices from text descriptions.
    static let voiceDesign = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

    /// RAM threshold in bytes (16 GB) above which the large model is recommended.
    static let ramThresholdBytes: UInt64 = 16 * 1024 * 1024 * 1024
}

/// Files required for a complete model download.
enum TTSModelFiles {
    static let required: [String] = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "model.safetensors",
    ]
}

/// Progress callback type for model downloads.
/// - Parameters:
///   - bytesDownloaded: Total bytes downloaded so far for the current file.
///   - totalBytes: Total expected bytes for the current file (nil if unknown).
///   - fileName: Name of the file currently being downloaded.
typealias DownloadProgress = @Sendable (Int64, Int64?, String) -> Void

/// Actor that manages TTS model downloads and availability checks for the diga CLI.
///
/// Models are stored in `~/Library/SharedModels/` via SwiftAcervo,
/// enabling model sharing across the intrusive-memory ecosystem.
actor DigaModelManager {

    // MARK: - Properties

    /// Base directory for all shared models (via Acervo).
    var modelsDirectory: URL {
        Acervo.sharedModelsDirectory
    }

    // MARK: - Initialization

    /// Creates a new model manager.
    init() {}

    // MARK: - Directory Paths

    /// Returns the local directory for a given HuggingFace model ID.
    ///
    /// The model ID is slugified via Acervo's convention (replacing `/` with `_`).
    ///
    /// - Parameter modelId: The HuggingFace model identifier (e.g., `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`).
    /// - Returns: A file URL to the model's local directory.
    func modelDirectory(for modelId: String) throws -> URL {
        try Acervo.modelDirectory(for: modelId)
    }

    // MARK: - Availability

    /// Checks whether a model is available locally by looking for `config.json`
    /// in the model's Acervo directory.
    ///
    /// - Parameter modelId: The HuggingFace model identifier.
    /// - Returns: `true` if the model directory contains `config.json`.
    func isModelAvailable(_ modelId: String) -> Bool {
        Acervo.isModelAvailable(modelId)
    }

    // MARK: - Model Selection

    /// Returns the recommended model ID based on the system's physical memory.
    ///
    /// - 16 GB or more: returns the large (1.7B) model for better quality.
    /// - Less than 16 GB: returns the small (0.6B) model to fit in memory.
    ///
    /// - Returns: A HuggingFace model identifier string.
    nonisolated func recommendedModel() -> String {
        let ram = ProcessInfo.processInfo.physicalMemory
        return Self.recommendedModel(forRAMBytes: ram)
    }

    /// Pure function for model selection logic, testable without hardware dependency.
    ///
    /// - Parameter ramBytes: Physical memory in bytes.
    /// - Returns: The recommended model identifier.
    static func recommendedModel(forRAMBytes ramBytes: UInt64) -> String {
        if ramBytes >= TTSModelID.ramThresholdBytes {
            return TTSModelID.large
        } else {
            return TTSModelID.small
        }
    }

    // MARK: - Download

    /// Downloads a model from HuggingFace Hub if not already present, via SwiftAcervo.
    ///
    /// - Parameters:
    ///   - modelId: The HuggingFace model identifier.
    ///   - progress: Optional callback invoked with download progress updates.
    /// - Throws: If any download or file-write operation fails.
    func downloadModel(
        _ modelId: String,
        progress: DownloadProgress? = nil
    ) async throws {
        try await Acervo.ensureAvailable(
            modelId,
            files: TTSModelFiles.required
        ) { acervoProgress in
            progress?(
                acervoProgress.bytesDownloaded,
                acervoProgress.totalBytes,
                acervoProgress.fileName
            )
        }
    }
}

// MARK: - Progress Formatting

extension DigaModelManager {

    /// Formats a download progress update as a human-readable string for stderr output.
    ///
    /// - Parameters:
    ///   - bytesDownloaded: Bytes downloaded so far.
    ///   - totalBytes: Total expected bytes (nil if unknown).
    ///   - fileName: The file being downloaded.
    /// - Returns: A formatted progress string, e.g., `"Downloading config.json... 1.2 MB / 3.4 MB (35%)"`.
    static func formatProgress(
        bytesDownloaded: Int64,
        totalBytes: Int64?,
        fileName: String
    ) -> String {
        let downloadedStr = formatBytes(bytesDownloaded)

        if let total = totalBytes, total > 0 {
            let totalStr = formatBytes(total)
            let percentage = Int((Double(bytesDownloaded) / Double(total)) * 100)
            return "Downloading \(fileName)... \(downloadedStr) / \(totalStr) (\(percentage)%)"
        } else {
            return "Downloading \(fileName)... \(downloadedStr)"
        }
    }

    /// Formats a byte count as a human-readable string.
    ///
    /// - Parameter bytes: The number of bytes.
    /// - Returns: A string like `"1.2 MB"` or `"456 KB"`.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Prints a progress bar to stderr.
    ///
    /// - Parameters:
    ///   - bytesDownloaded: Bytes downloaded so far.
    ///   - totalBytes: Total expected bytes (nil if unknown).
    ///   - fileName: The file being downloaded.
    static func printProgress(
        bytesDownloaded: Int64,
        totalBytes: Int64?,
        fileName: String
    ) {
        let message = formatProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            fileName: fileName
        )
        // Carriage return to overwrite previous line on stderr
        FileHandle.standardError.write(Data("\r\(message)".utf8))

        // If download is complete for this file, add a newline
        if let total = totalBytes, bytesDownloaded >= total {
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }
}
