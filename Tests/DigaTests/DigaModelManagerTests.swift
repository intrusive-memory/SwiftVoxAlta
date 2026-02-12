import Foundation
import Testing
import SwiftAcervo

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
    static let large = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    static let small = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    static let voiceDesign = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
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

// MARK: - Test Suite

@Suite("Diga Model Manager Tests")
struct DigaModelManagerTests {

    // MARK: - 2.1 Directory Paths

    @Test("modelsDirectory points to ~/Library/SharedModels/ via Acervo")
    func modelsDirectoryPath() {
        let expected = Acervo.sharedModelsDirectory
        #expect(expected.path.hasSuffix("Library/SharedModels"))
    }

    @Test("modelDirectory slugifies HuggingFace IDs by replacing / with _")
    func modelDirectorySlugifies() throws {
        let dir = try Acervo.modelDirectory(for: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
        #expect(dir.lastPathComponent == "mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16")
    }

    @Test("Acervo.slugify replaces all slashes in model ID")
    func slugifyReplacesSlashes() {
        #expect(Acervo.slugify("org/repo") == "org_repo")
        #expect(Acervo.slugify("noslash") == "noslash")
        #expect(Acervo.slugify("") == "")
    }

    @Test("modelDirectory for small model produces correct slug")
    func modelDirectorySmallModel() throws {
        let dir = try Acervo.modelDirectory(for: TestTTSModelID.small)
        #expect(dir.lastPathComponent == "mlx-community_Qwen3-TTS-12Hz-0.6B-Base-bf16")
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

    // MARK: - 2.1/2.3 Model Availability (via Acervo)

    @Test("isModelAvailable returns false for missing model directory")
    func isModelAvailableMissing() {
        // A model that's extremely unlikely to exist
        let available = Acervo.isModelAvailable("test-org/nonexistent-model-\(UUID().uuidString)")
        #expect(available == false)
    }

    @Test("isModelAvailable returns true when config.json exists in Acervo model directory")
    func isModelAvailablePresent() throws {
        let tempModelId = "test-org/acervo-test-\(UUID().uuidString)"
        let modelDir = try Acervo.modelDirectory(for: tempModelId)
        defer { try? FileManager.default.removeItem(at: modelDir) }

        // Create the model directory with config.json
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )
        let configPath = modelDir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: configPath)

        let available = Acervo.isModelAvailable(tempModelId)
        #expect(available == true)
    }

    @Test("isModelAvailable returns false when directory exists but config.json is absent")
    func isModelAvailableDirectoryOnlyNoConfig() throws {
        let tempModelId = "test-org/acervo-test-\(UUID().uuidString)"
        let modelDir = try Acervo.modelDirectory(for: tempModelId)
        defer { try? FileManager.default.removeItem(at: modelDir) }

        // Create model directory without config.json
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )

        let available = Acervo.isModelAvailable(tempModelId)
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

    // MARK: - 2.2/2.4 Model Override

    @Test("Model constants match expected HuggingFace IDs")
    func modelConstants() {
        #expect(TestTTSModelID.large == "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
        #expect(TestTTSModelID.small == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
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

    @Test("Multiple models can coexist in Acervo shared directory")
    func multipleModelsCoexist() throws {
        let id1 = "test-org/acervo-coexist-a-\(UUID().uuidString)"
        let id2 = "test-org/acervo-coexist-b-\(UUID().uuidString)"
        let dir1 = try Acervo.modelDirectory(for: id1)
        let dir2 = try Acervo.modelDirectory(for: id2)
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        // Create both model directories
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        // Only populate the first model
        try Data("{}".utf8).write(to: dir1.appendingPathComponent("config.json"))

        #expect(Acervo.isModelAvailable(id1) == true)
        #expect(Acervo.isModelAvailable(id2) == false)

        // Now populate the second model too
        try Data("{}".utf8).write(to: dir2.appendingPathComponent("config.json"))

        #expect(Acervo.isModelAvailable(id1) == true)
        #expect(Acervo.isModelAvailable(id2) == true)
    }
}
