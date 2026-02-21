import Foundation
import Testing
import VoxFormat
@testable import SwiftVoxAlta

@Suite("VoxImporter Tests")
struct VoxImporterTests {

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-importer-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Helper: create a .vox file with optional clone prompt for testing.
    private func createTestVox(
        name: String = "ImportTest",
        description: String = "A test voice for import validation.",
        method: String = "designed",
        clonePromptData: Data? = nil,
        clonePromptModelRepo: Qwen3TTSModelRepo = .base1_7B,
        includeReference: Bool = false,
        in directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var refURLs: [URL] = []
        var refPaths: [String] = []
        if includeReference {
            let refURL = directory.appendingPathComponent("ref-audio.wav")
            try Data(repeating: 0x00, count: 44).write(to: refURL)
            refURLs.append(refURL)
            refPaths.append(refURL.path)
        }

        let manifest = VoxExporter.buildManifest(
            name: name,
            description: description,
            voiceType: method,
            referenceAudioPaths: refPaths
        )
        let voxURL = directory.appendingPathComponent("\(name).vox")
        try VoxExporter.export(
            manifest: manifest,
            clonePromptData: clonePromptData,
            clonePromptModelRepo: clonePromptModelRepo,
            referenceAudioURLs: refURLs,
            to: voxURL
        )
        return voxURL
    }

    // MARK: - Import Tests

    @Test("importVox extracts clone prompt data")
    func importWithClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let promptData = Data(repeating: 0xEF, count: 64)
        let voxURL = try createTestVox(clonePromptData: promptData, in: tempDir)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.clonePromptData == promptData)
        #expect(result.name == "ImportTest")
    }

    @Test("importVox returns nil clonePromptData when none embedded")
    func importWithoutClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let voxURL = try createTestVox(in: tempDir)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.clonePromptData == nil)
        #expect(result.clonePromptsByModel.isEmpty)
    }

    @Test("importVox preserves metadata from manifest")
    func importPreservesMetadata() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let voxURL = try createTestVox(
            name: "MetadataVoice",
            description: "A detailed voice description for testing.",
            method: "cloned",
            in: tempDir
        )

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.name == "MetadataVoice")
        #expect(result.description == "A detailed voice description for testing.")
        #expect(result.method == "cloned")
    }

    @Test("importVox extracts sample audio data")
    func importWithSampleAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let sampleData = Data(repeating: 0xDA, count: 128)
        let voxURL = try createTestVox(in: tempDir)

        // Add sample audio to the .vox file.
        try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.sampleAudioData == sampleData)
    }

    @Test("importVox returns nil sampleAudioData when none embedded")
    func importWithoutSampleAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let voxURL = try createTestVox(in: tempDir)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.sampleAudioData == nil)
    }

    @Test("importVox throws for invalid file")
    func importInvalidFile() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write garbage data as a .vox file.
        let badURL = tempDir.appendingPathComponent("bad.vox")
        try Data("not a zip file".utf8).write(to: badURL)

        #expect(throws: VoxAltaError.self) {
            try VoxImporter.importVox(from: badURL)
        }
    }

    @Test("importVox throws for nonexistent file")
    func importNonexistentFile() throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).vox")

        #expect(throws: VoxAltaError.self) {
            try VoxImporter.importVox(from: fakeURL)
        }
    }

    // MARK: - Multi-Model Import Tests

    @Test("importVox extracts both 0.6B and 1.7B clone prompts")
    func importMultiModelClonePrompts() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        // Create with 1.7B clone prompt.
        let data1_7B = Data(repeating: 0xAA, count: 256)
        let voxURL = try createTestVox(
            name: "MultiImport",
            clonePromptData: data1_7B,
            clonePromptModelRepo: .base1_7B,
            in: tempDir
        )

        // Add 0.6B clone prompt.
        let data0_6B = Data(repeating: 0xBB, count: 128)
        try VoxExporter.updateClonePrompt(
            in: voxURL,
            clonePromptData: data0_6B,
            modelRepo: .base0_6B
        )

        let result = try VoxImporter.importVox(from: voxURL)

        // Both should be in clonePromptsByModel.
        #expect(result.clonePromptsByModel.count == 2)
        #expect(result.clonePromptsByModel["qwen3-tts-1.7b"] == data1_7B)
        #expect(result.clonePromptsByModel["qwen3-tts-0.6b"] == data0_6B)

        // Backward-compatible property should prefer 1.7B.
        #expect(result.clonePromptData == data1_7B)
    }

    @Test("importVox handles legacy single-path .vox files")
    func importLegacySinglePath() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Manually create a legacy .vox with the old path "qwen3-tts/clone-prompt.bin"
        let manifest = VoxExporter.buildManifest(
            name: "LegacyVoice",
            description: "A legacy voice with old-format clone prompt.",
            voiceType: "designed"
        )

        let legacyData = Data(repeating: 0xCC, count: 100)
        let embeddings: [String: Data] = [
            "qwen3-tts/clone-prompt.bin": legacyData
        ]

        let voxFile = VoxFile(
            manifest: manifest,
            referenceAudio: [:],
            embeddings: embeddings
        )
        let voxURL = tempDir.appendingPathComponent("legacy.vox")
        let writer = VoxWriter()
        try writer.write(voxFile, to: voxURL)

        let result = try VoxImporter.importVox(from: voxURL)

        // Legacy data should appear as 1.7B.
        #expect(result.clonePromptsByModel["qwen3-tts-1.7b"] == legacyData)
        #expect(result.clonePromptData == legacyData)
    }

    @Test("importVox model-specific query returns correct data")
    func importModelSpecificQuery() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        // Create with 1.7B.
        let data1_7B = Data(repeating: 0xDD, count: 200)
        let voxURL = try createTestVox(
            name: "QueryTest",
            clonePromptData: data1_7B,
            clonePromptModelRepo: .base1_7B,
            in: tempDir
        )

        // Add 0.6B.
        let data0_6B = Data(repeating: 0xEE, count: 100)
        try VoxExporter.updateClonePrompt(
            in: voxURL,
            clonePromptData: data0_6B,
            modelRepo: .base0_6B
        )

        let result = try VoxImporter.importVox(from: voxURL)

        // Query by model slug.
        #expect(result.clonePromptData(for: "0.6b") == data0_6B)
        #expect(result.clonePromptData(for: "1.7b") == data1_7B)
        #expect(result.clonePromptData(for: "2.0b") == nil)
    }
}
