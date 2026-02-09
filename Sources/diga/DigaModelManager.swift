import Foundation

/// Known TTS model identifiers from HuggingFace.
enum TTSModelID {
    /// Large model (1.7B parameters) — better quality, requires 16GB+ RAM.
    static let large = "mlx-community/Qwen3-TTS-12Hz-1.7B"
    /// Small model (0.6B parameters) — fits in less RAM.
    static let small = "mlx-community/Qwen3-TTS-12Hz-0.6B"

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
/// Models are stored under `~/Library/Caches/intrusive-memory/Models/TTS/`,
/// matching the SwiftBruja LLM convention for cache directories.
actor DigaModelManager {

    // MARK: - Properties

    /// Base directory for all TTS model caches.
    let modelsDirectory: URL

    /// File manager used for disk operations (injectable for testing).
    private let fileManager: FileManager

    /// URL session used for downloads (injectable for testing).
    private let urlSession: URLSession

    // MARK: - Initialization

    /// Creates a new model manager.
    ///
    /// - Parameters:
    ///   - modelsDirectory: Override the default models directory. Pass `nil` for the standard
    ///     `~/Library/Caches/intrusive-memory/Models/TTS/` location.
    ///   - fileManager: File manager for disk operations. Defaults to `.default`.
    ///   - urlSession: URL session for downloads. Defaults to `.shared`.
    init(
        modelsDirectory: URL? = nil,
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared
    ) {
        if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            // ~/Library/Caches/intrusive-memory/Models/TTS/
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.modelsDirectory = caches
                .appendingPathComponent("intrusive-memory", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("TTS", isDirectory: true)
        }
        self.fileManager = fileManager
        self.urlSession = urlSession
    }

    // MARK: - Directory Paths

    /// Returns the local directory for a given HuggingFace model ID.
    ///
    /// The model ID's `/` separator is replaced with `_` to create a valid directory name.
    /// For example, `mlx-community/Qwen3-TTS-12Hz-1.7B` becomes
    /// `mlx-community_Qwen3-TTS-12Hz-1.7B`.
    ///
    /// - Parameter modelId: The HuggingFace model identifier (e.g., `mlx-community/Qwen3-TTS-12Hz-1.7B`).
    /// - Returns: A file URL to the model's local directory.
    func modelDirectory(for modelId: String) -> URL {
        let slug = Self.slugify(modelId)
        return modelsDirectory.appendingPathComponent(slug, isDirectory: true)
    }

    /// Converts a HuggingFace model ID to a filesystem-safe directory name.
    ///
    /// - Parameter modelId: The HuggingFace model identifier.
    /// - Returns: The slugified model identifier with `/` replaced by `_`.
    static func slugify(_ modelId: String) -> String {
        modelId.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Availability

    /// Checks whether a model is available locally by looking for `config.json`
    /// in the model's directory.
    ///
    /// - Parameter modelId: The HuggingFace model identifier.
    /// - Returns: `true` if the model directory contains `config.json`.
    func isModelAvailable(_ modelId: String) -> Bool {
        let configPath = modelDirectory(for: modelId)
            .appendingPathComponent("config.json")
            .path
        return fileManager.fileExists(atPath: configPath)
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

    /// Downloads a model from HuggingFace Hub if not already present.
    ///
    /// Downloads each required file (`config.json`, `tokenizer.json`, `tokenizer_config.json`,
    /// `model.safetensors`) into the model's local directory.
    ///
    /// - Parameters:
    ///   - modelId: The HuggingFace model identifier.
    ///   - progress: Optional callback invoked with download progress updates.
    /// - Throws: If any download or file-write operation fails.
    func downloadModel(
        _ modelId: String,
        progress: DownloadProgress? = nil
    ) async throws {
        // Skip if model already exists
        if isModelAvailable(modelId) {
            return
        }

        let modelDir = modelDirectory(for: modelId)

        // Create directory structure
        try fileManager.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Download each required file
        for fileName in TTSModelFiles.required {
            let fileURL = Self.huggingFaceFileURL(modelId: modelId, fileName: fileName)
            let destinationURL = modelDir.appendingPathComponent(fileName)

            // Skip individual files that already exist
            if fileManager.fileExists(atPath: destinationURL.path) {
                continue
            }

            try await downloadFile(
                from: fileURL,
                to: destinationURL,
                fileName: fileName,
                progress: progress
            )
        }
    }

    // MARK: - Private Helpers

    /// Constructs the HuggingFace download URL for a specific file in a model repository.
    ///
    /// - Parameters:
    ///   - modelId: The HuggingFace model identifier (e.g., `mlx-community/Qwen3-TTS-12Hz-1.7B`).
    ///   - fileName: The file name to download (e.g., `config.json`).
    /// - Returns: The full URL to the file on HuggingFace Hub.
    static func huggingFaceFileURL(modelId: String, fileName: String) -> URL {
        URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(fileName)")!
    }

    /// Downloads a single file from a URL to a local destination.
    ///
    /// - Parameters:
    ///   - url: The remote file URL.
    ///   - destination: The local file URL to write to.
    ///   - fileName: Display name for progress reporting.
    ///   - progress: Optional progress callback.
    private func downloadFile(
        from url: URL,
        to destination: URL,
        fileName: String,
        progress: DownloadProgress?
    ) async throws {
        let (asyncBytes, response) = try await urlSession.bytes(from: url)

        let totalBytes: Int64?
        if let httpResponse = response as? HTTPURLResponse {
            let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length")
            totalBytes = contentLength.flatMap(Int64.init)
        } else {
            totalBytes = nil
        }

        var data = Data()
        if let total = totalBytes {
            data.reserveCapacity(Int(total))
        }

        var bytesReceived: Int64 = 0
        for try await byte in asyncBytes {
            data.append(byte)
            bytesReceived += 1

            // Report progress every 64KB to avoid excessive callback overhead
            if bytesReceived % (64 * 1024) == 0 {
                progress?(bytesReceived, totalBytes, fileName)
            }
        }

        // Final progress report
        progress?(bytesReceived, totalBytes, fileName)

        // Write to disk
        try data.write(to: destination, options: .atomic)
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
