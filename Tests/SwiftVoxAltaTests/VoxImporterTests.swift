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

    /// Helper: create a .vox file with optional clone prompt using container-first API.
    private func createTestVox(
        name: String = "ImportTest",
        description: String = "A test voice for import validation.",
        method: String = "designed",
        clonePromptData: Data? = nil,
        includeReference: Bool = false,
        in directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let vox = VoxFile(name: name, description: description)
        vox.manifest.provenance = VoxManifest.Provenance(method: method, engine: "qwen3-tts")

        if let promptData = clonePromptData {
            try vox.add(promptData, at: VoxExporter.clonePromptPath(for: .base1_7B), metadata: [
                "model": Qwen3TTSModelRepo.base1_7B.rawValue,
                "engine": "qwen3-tts",
                "format": "bin",
            ])
        }

        if includeReference {
            let refData = Data(repeating: 0x00, count: 44)
            try vox.add(refData, at: "reference/ref-audio.wav", metadata: [
                "transcript": "",
                "language": "en-US",
            ])
        }

        let voxURL = directory.appendingPathComponent("\(name).vox")
        try vox.write(to: voxURL)
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

    @Test("importVox extracts reference audio")
    func importWithReferenceAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let voxURL = try createTestVox(includeReference: true, in: tempDir)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(!result.referenceAudio.isEmpty)
        #expect(result.referenceAudio["ref-audio.wav"] != nil)
    }

    @Test("importVox includes supportedModels")
    func importReportsSupportedModels() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let promptData = Data(repeating: 0xAB, count: 32)
        let voxURL = try createTestVox(clonePromptData: promptData, in: tempDir)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(!result.supportedModels.isEmpty)
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
}
