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
