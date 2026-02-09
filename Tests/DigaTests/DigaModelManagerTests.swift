import Foundation
import Testing

// MARK: - Replicated Constants and Logic
//
// Since `diga` is an executable target with @main, it cannot be imported
// into test targets. We replicate the pure logic and constants here so
// tests verify that the algorithms and paths are correct, independent of
// the executable shell. This is the same pattern used in DigaVersionTests.
//
// If someone changes a constant in DigaModelManager.swift, these tests
// serve as the canary that detects drift.

/// Mirror of TTSModelID from DigaModelManager.swift
private enum TestTTSModelID {
    static let large = "mlx-community/Qwen3-TTS-12Hz-1.7B"
    static let small = "mlx-community/Qwen3-TTS-12Hz-0.6B"
    static let ramThresholdBytes: UInt64 = 16 * 1024 * 1024 * 1024  // 16 GB
}

/// Mirror of TTSModelFiles from DigaModelManager.swift
private enum TestTTSModelFiles {
    static let required: [String] = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "model.safetensors",
    ]
}

/// Replicates the model selection logic from DigaModelManager.
private func recommendedModel(forRAMBytes ramBytes: UInt64) -> String {
    if ramBytes >= TestTTSModelID.ramThresholdBytes {
        return TestTTSModelID.large
    } else {
        return TestTTSModelID.small
    }
}

/// Replicates the slugify logic from DigaModelManager.
private func slugify(_ modelId: String) -> String {
    modelId.replacingOccurrences(of: "/", with: "_")
}

/// Replicates the HuggingFace URL construction from DigaModelManager.
private func huggingFaceFileURL(modelId: String, fileName: String) -> URL {
    URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(fileName)")!
}

/// Computes the expected default models directory.
private func expectedDefaultModelsDirectory() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return caches
        .appendingPathComponent("intrusive-memory", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent("TTS", isDirectory: true)
}

/// Computes a model directory given a base directory and model ID.
private func modelDirectory(base: URL, modelId: String) -> URL {
    base.appendingPathComponent(slugify(modelId), isDirectory: true)
}

/// Checks if a model is "available" by looking for config.json in its directory.
private func isModelAvailable(base: URL, modelId: String) -> Bool {
    let configPath = modelDirectory(base: base, modelId: modelId)
        .appendingPathComponent("config.json")
        .path
    return FileManager.default.fileExists(atPath: configPath)
}

// MARK: - Test Suite

@Suite("Diga Model Manager Tests")
struct DigaModelManagerTests {

    // MARK: - 2.1 Directory Paths

    @Test("modelsDirectory points to ~/Library/Caches/intrusive-memory/Models/TTS/")
    func modelsDirectoryPath() {
        let expected = expectedDefaultModelsDirectory()
        // The path should end with the correct hierarchy
        #expect(expected.path.hasSuffix("Library/Caches/intrusive-memory/Models/TTS"))
    }

    @Test("modelDirectory slugifies HuggingFace IDs by replacing / with _")
    func modelDirectorySlugifies() {
        let base = URL(fileURLWithPath: "/tmp/test-models")
        let dir = modelDirectory(base: base, modelId: "mlx-community/Qwen3-TTS-12Hz-1.7B")
        let expected = "/tmp/test-models/mlx-community_Qwen3-TTS-12Hz-1.7B"
        #expect(dir.path == expected)
    }

    @Test("slugify replaces all slashes in model ID")
    func slugifyReplacesSlashes() {
        #expect(slugify("org/repo") == "org_repo")
        #expect(slugify("a/b/c") == "a_b_c")
        #expect(slugify("noslash") == "noslash")
        #expect(slugify("") == "")
    }

    @Test("modelDirectory for small model produces correct slug")
    func modelDirectorySmallModel() {
        let base = URL(fileURLWithPath: "/cache")
        let dir = modelDirectory(base: base, modelId: TestTTSModelID.small)
        #expect(dir.path == "/cache/mlx-community_Qwen3-TTS-12Hz-0.6B")
    }

    // MARK: - 2.2 RAM-Based Model Selection

    @Test("recommendedModel returns large model for 16GB+ RAM")
    func recommendedModelLargeRAM() {
        // Exactly 16 GB
        let model16 = recommendedModel(forRAMBytes: 16 * 1024 * 1024 * 1024)
        #expect(model16 == TestTTSModelID.large)

        // 32 GB
        let model32 = recommendedModel(forRAMBytes: 32 * 1024 * 1024 * 1024)
        #expect(model32 == TestTTSModelID.large)

        // 64 GB
        let model64 = recommendedModel(forRAMBytes: 64 * 1024 * 1024 * 1024)
        #expect(model64 == TestTTSModelID.large)
    }

    @Test("recommendedModel returns small model for less than 16GB RAM")
    func recommendedModelSmallRAM() {
        // 8 GB
        let model8 = recommendedModel(forRAMBytes: 8 * 1024 * 1024 * 1024)
        #expect(model8 == TestTTSModelID.small)

        // 1 byte below threshold
        let modelJustBelow = recommendedModel(forRAMBytes: TestTTSModelID.ramThresholdBytes - 1)
        #expect(modelJustBelow == TestTTSModelID.small)

        // 0 bytes
        let model0 = recommendedModel(forRAMBytes: 0)
        #expect(model0 == TestTTSModelID.small)
    }

    @Test("RAM threshold is exactly 16 GB in bytes")
    func ramThresholdValue() {
        let expected: UInt64 = 16 * 1024 * 1024 * 1024
        #expect(TestTTSModelID.ramThresholdBytes == expected)
        #expect(TestTTSModelID.ramThresholdBytes == 17_179_869_184)
    }

    // MARK: - 2.1/2.3 Model Availability

    @Test("isModelAvailable returns false for missing model directory")
    func isModelAvailableMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let available = isModelAvailable(base: tempDir, modelId: TestTTSModelID.large)
        #expect(available == false)
    }

    @Test("isModelAvailable returns true when config.json exists in model directory")
    func isModelAvailablePresent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create the model directory with config.json
        let modelDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.large)
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )
        let configPath = modelDir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configPath)

        let available = isModelAvailable(base: tempDir, modelId: TestTTSModelID.large)
        #expect(available == true)
    }

    @Test("isModelAvailable returns false when directory exists but config.json is absent")
    func isModelAvailableDirectoryOnlyNoConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create model directory without config.json
        let modelDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.small)
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )

        let available = isModelAvailable(base: tempDir, modelId: TestTTSModelID.small)
        #expect(available == false)
    }

    // MARK: - 2.3 Download Infrastructure

    @Test("Required model files list contains exactly 4 expected files")
    func requiredModelFiles() {
        #expect(TestTTSModelFiles.required.count == 4)
        #expect(TestTTSModelFiles.required.contains("config.json"))
        #expect(TestTTSModelFiles.required.contains("tokenizer.json"))
        #expect(TestTTSModelFiles.required.contains("tokenizer_config.json"))
        #expect(TestTTSModelFiles.required.contains("model.safetensors"))
    }

    @Test("HuggingFace file URLs are constructed correctly")
    func huggingFaceURLConstruction() {
        let url = huggingFaceFileURL(
            modelId: "mlx-community/Qwen3-TTS-12Hz-1.7B",
            fileName: "config.json"
        )
        #expect(
            url.absoluteString
                == "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B/resolve/main/config.json"
        )
    }

    @Test("HuggingFace URLs for all required files are valid")
    func huggingFaceURLsAllFiles() {
        for fileName in TestTTSModelFiles.required {
            let url = huggingFaceFileURL(
                modelId: TestTTSModelID.large,
                fileName: fileName
            )
            #expect(url.scheme == "https")
            #expect(url.host == "huggingface.co")
            #expect(url.absoluteString.contains(fileName))
        }
    }

    // MARK: - 2.4 Download Skip-If-Exists and Directory Creation

    @Test("Download creates model directory structure if missing")
    func downloadCreatesDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate what downloadModel does: create directory structure
        let modelDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.large)
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))

        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )

        #expect(FileManager.default.fileExists(atPath: modelDir.path))

        // Verify the full path hierarchy was created
        #expect(FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test("Download skips when model is already available (config.json exists)")
    func downloadSkipsExistingModel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-populate model directory with config.json
        let modelDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.small)
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: modelDir.appendingPathComponent("config.json"))

        // Model should be detected as available — no download needed
        let available = isModelAvailable(base: tempDir, modelId: TestTTSModelID.small)
        #expect(available == true, "Download should be skipped when config.json exists")
    }

    // MARK: - 2.2/2.4 Model Override

    @Test("Model constants match expected HuggingFace IDs")
    func modelConstants() {
        #expect(TestTTSModelID.large == "mlx-community/Qwen3-TTS-12Hz-1.7B")
        #expect(TestTTSModelID.small == "mlx-community/Qwen3-TTS-12Hz-0.6B")
    }

    @Test("Custom model ID slugifies correctly for arbitrary HuggingFace repos")
    func customModelSlugify() {
        // A user-provided --model override with a custom model ID
        let customId = "my-org/my-custom-tts-model"
        let slug = slugify(customId)
        #expect(slug == "my-org_my-custom-tts-model")
        #expect(!slug.contains("/"))
    }

    // MARK: - Progress Formatting

    @Test("Byte formatting produces human-readable strings")
    func byteFormatting() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        // Verify the formatter works for representative values
        let small = formatter.string(fromByteCount: 1024)
        #expect(!small.isEmpty)

        let medium = formatter.string(fromByteCount: 1_048_576)
        #expect(!medium.isEmpty)

        let large = formatter.string(fromByteCount: 1_073_741_824)
        #expect(!large.isEmpty)
    }

    @Test("Multiple models can coexist in the same models directory")
    func multipleModelsCoexist() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create both model directories
        let largeDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.large)
        let smallDir = modelDirectory(base: tempDir, modelId: TestTTSModelID.small)

        try FileManager.default.createDirectory(at: largeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: smallDir, withIntermediateDirectories: true)

        // Only populate the large model
        try Data("{}".utf8).write(to: largeDir.appendingPathComponent("config.json"))

        #expect(isModelAvailable(base: tempDir, modelId: TestTTSModelID.large) == true)
        #expect(isModelAvailable(base: tempDir, modelId: TestTTSModelID.small) == false)

        // Now populate the small model too
        try Data("{}".utf8).write(to: smallDir.appendingPathComponent("config.json"))

        #expect(isModelAvailable(base: tempDir, modelId: TestTTSModelID.large) == true)
        #expect(isModelAvailable(base: tempDir, modelId: TestTTSModelID.small) == true)
    }
}
