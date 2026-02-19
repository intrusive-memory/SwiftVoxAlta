import Foundation
import Testing
import VoxFormat
@testable import SwiftVoxAlta

@Suite("VoxExporter Tests")
struct VoxExporterTests {

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-exporter-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Manifest Building

    @Test("buildManifest from VoiceLock maps fields correctly")
    func buildManifestFromVoiceLock() {
        let lock = VoiceLock(
            characterName: "ELENA",
            clonePromptData: Data([1, 2, 3]),
            designInstruction: "A warm, elderly female voice with Eastern European accent.",
            lockedAt: Date(timeIntervalSinceReferenceDate: 10000)
        )

        let manifest = VoxExporter.buildManifest(from: lock, voiceType: "designed")

        #expect(manifest.voice.name == "ELENA")
        #expect(manifest.voice.description == "A warm, elderly female voice with Eastern European accent.")
        #expect(manifest.provenance?.method == "designed")
        #expect(manifest.provenance?.engine == "qwen3-tts")
        #expect(manifest.created == lock.lockedAt)
        #expect(manifest.voxVersion == "0.1.0")
        #expect(!manifest.id.isEmpty)
    }

    @Test("buildManifest from metadata populates name and description")
    func buildManifestFromMetadata() {
        let manifest = VoxExporter.buildManifest(
            name: "Narrator",
            description: "A deep, resonant male narrator voice.",
            voiceType: "cloned"
        )

        #expect(manifest.voice.name == "Narrator")
        #expect(manifest.voice.description == "A deep, resonant male narrator voice.")
        #expect(manifest.provenance?.method == "cloned")
    }

    @Test("buildManifest uses fallback description when too short")
    func buildManifestFallbackDescription() {
        let manifest = VoxExporter.buildManifest(
            name: "Test",
            description: "short",
            voiceType: "designed"
        )

        #expect(manifest.voice.description == "Voice identity for Test.")
    }

    @Test("buildManifest includes reference audio entries")
    func buildManifestWithReferenceAudio() {
        let manifest = VoxExporter.buildManifest(
            name: "Clone",
            description: nil,
            voiceType: "cloned",
            referenceAudioPaths: ["/path/to/sample.wav"]
        )

        #expect(manifest.referenceAudio?.count == 1)
        #expect(manifest.referenceAudio?[0].file == "reference/sample.wav")
    }

    // MARK: - Export

    @Test("export creates valid .vox with clone prompt")
    func exportWithClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifest = VoxExporter.buildManifest(
            name: "TestVoice",
            description: "A test voice for export validation.",
            voiceType: "designed"
        )
        let cloneData = Data(repeating: 0xAB, count: 256)
        let voxURL = tempDir.appendingPathComponent("test.vox")

        try VoxExporter.export(
            manifest: manifest,
            clonePromptData: cloneData,
            to: voxURL
        )

        // Verify the file exists and can be read back.
        #expect(FileManager.default.fileExists(atPath: voxURL.path))

        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        #expect(readBack.manifest.voice.name == "TestVoice")

        // Verify embeddings has clone prompt.
        let roundTripped = readBack.embeddings["qwen3-tts/clone-prompt.bin"]
        #expect(roundTripped == cloneData)
    }

    @Test("export creates valid .vox without clone prompt")
    func exportWithoutClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifest = VoxExporter.buildManifest(
            name: "ManifestOnly",
            description: "A voice with only manifest data.",
            voiceType: "designed"
        )
        let voxURL = tempDir.appendingPathComponent("manifest-only.vox")

        try VoxExporter.export(manifest: manifest, to: voxURL)

        #expect(FileManager.default.fileExists(atPath: voxURL.path))

        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        #expect(readBack.manifest.voice.name == "ManifestOnly")
    }

    @Test("export includes reference audio in archive")
    func exportWithReferenceAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a fake reference audio file.
        let refURL = tempDir.appendingPathComponent("reference.wav")
        try Data(repeating: 0x00, count: 44).write(to: refURL)

        let manifest = VoxExporter.buildManifest(
            name: "ClonedVoice",
            description: "A voice cloned from reference audio.",
            voiceType: "cloned",
            referenceAudioPaths: [refURL.path]
        )
        let voxURL = tempDir.appendingPathComponent("cloned.vox")

        try VoxExporter.export(
            manifest: manifest,
            referenceAudioURLs: [refURL],
            to: voxURL
        )

        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        #expect(!readBack.referenceAudio.isEmpty)
    }

    @Test("updateSampleAudio adds sample audio to existing .vox")
    func updateSampleAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // First export without sample audio.
        let manifest = VoxExporter.buildManifest(
            name: "SampleTest",
            description: "Testing sample audio update flow.",
            voiceType: "designed"
        )
        let voxURL = tempDir.appendingPathComponent("sample.vox")
        try VoxExporter.export(manifest: manifest, to: voxURL)

        // Now update with sample audio.
        let sampleData = Data(repeating: 0xAA, count: 256)
        try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

        // Verify the sample audio is now present.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        let roundTripped = readBack.embeddings[VoxExporter.sampleAudioEmbeddingPath]
        #expect(roundTripped == sampleData)
    }

    @Test("updateSampleAudio preserves existing clone prompt")
    func updateSampleAudioPreservesClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export with clone prompt.
        let manifest = VoxExporter.buildManifest(
            name: "PreserveTest",
            description: "Testing that sample audio doesn't clobber clone prompt.",
            voiceType: "designed"
        )
        let cloneData = Data(repeating: 0xBB, count: 64)
        let voxURL = tempDir.appendingPathComponent("preserve.vox")
        try VoxExporter.export(manifest: manifest, clonePromptData: cloneData, to: voxURL)

        // Add sample audio.
        let sampleData = Data(repeating: 0xCC, count: 128)
        try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

        // Both should be present.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        #expect(readBack.embeddings["qwen3-tts/clone-prompt.bin"] == cloneData)
        #expect(readBack.embeddings[VoxExporter.sampleAudioEmbeddingPath] == sampleData)
    }

    @Test("updateClonePrompt adds prompt to existing .vox")
    func updateClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // First export without clone prompt.
        let manifest = VoxExporter.buildManifest(
            name: "UpdateTest",
            description: "Testing clone prompt update flow.",
            voiceType: "designed"
        )
        let voxURL = tempDir.appendingPathComponent("update.vox")
        try VoxExporter.export(manifest: manifest, to: voxURL)

        // Now update with a clone prompt.
        let promptData = Data(repeating: 0xCD, count: 128)
        try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: promptData)

        // Verify the clone prompt is now present.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        let roundTripped = readBack.embeddings["qwen3-tts/clone-prompt.bin"]
        #expect(roundTripped == promptData)
    }
}
