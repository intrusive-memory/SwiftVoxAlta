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
        #expect(manifest.voxVersion == VoxFormat.currentVersion)
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

    // MARK: - Model-Specific Path Helpers

    @Test("modelSizeSlug returns correct slugs for all repos")
    func modelSizeSlugs() {
        #expect(VoxExporter.modelSizeSlug(for: .base0_6B) == "0.6b")
        #expect(VoxExporter.modelSizeSlug(for: .base1_7B) == "1.7b")
        #expect(VoxExporter.modelSizeSlug(for: .base1_7B_8bit) == "1.7b")
        #expect(VoxExporter.modelSizeSlug(for: .base1_7B_4bit) == "1.7b")
        #expect(VoxExporter.modelSizeSlug(for: .customVoice0_6B) == "0.6b")
        #expect(VoxExporter.modelSizeSlug(for: .customVoice1_7B) == "1.7b")
        #expect(VoxExporter.modelSizeSlug(for: .voiceDesign1_7B) == "1.7b")
    }

    @Test("clonePromptEmbeddingPath returns model-specific paths")
    func clonePromptEmbeddingPaths() {
        #expect(VoxExporter.clonePromptEmbeddingPath(for: .base0_6B) == "qwen3-tts/0.6b/clone-prompt.bin")
        #expect(VoxExporter.clonePromptEmbeddingPath(for: .base1_7B) == "qwen3-tts/1.7b/clone-prompt.bin")
    }

    @Test("clonePromptEntryKey returns model-specific keys")
    func clonePromptEntryKeys() {
        #expect(VoxExporter.clonePromptEntryKey(for: .base0_6B) == "qwen3-tts-0.6b")
        #expect(VoxExporter.clonePromptEntryKey(for: .base1_7B) == "qwen3-tts-1.7b")
    }

    // MARK: - Export

    @Test("export with 0.6B model uses model-specific path")
    func exportWithModelSpecificPath() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manifest = VoxExporter.buildManifest(
            name: "SmallModelVoice",
            description: "A voice exported with the 0.6B model.",
            voiceType: "designed"
        )
        let cloneData = Data(repeating: 0xAB, count: 256)
        let voxURL = tempDir.appendingPathComponent("small.vox")

        try VoxExporter.export(
            manifest: manifest,
            clonePromptData: cloneData,
            clonePromptModelRepo: .base0_6B,
            to: voxURL
        )

        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)

        // Verify model-specific embedding path.
        let roundTripped = readBack.embeddings["qwen3-tts/0.6b/clone-prompt.bin"]
        #expect(roundTripped == cloneData)

        // Verify embedding entry uses 0.6B key.
        let entry = readBack.manifest.embeddingEntries?["qwen3-tts-0.6b"]
        #expect(entry != nil)
        #expect(entry?.engine == "qwen3-tts")
        #expect(entry?.format == "bin")
        #expect(entry?.file == "qwen3-tts/0.6b/clone-prompt.bin")
        #expect(entry?.model == Qwen3TTSModelRepo.base0_6B.rawValue)
    }

    @Test("export creates valid .vox with clone prompt (default 1.7B)")
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

        // Verify embeddings has clone prompt at model-specific path.
        let roundTripped = readBack.embeddings["qwen3-tts/1.7b/clone-prompt.bin"]
        #expect(roundTripped == cloneData)

        // Verify embedding entry metadata uses 1.7B key.
        let entry = readBack.manifest.embeddingEntries?["qwen3-tts-1.7b"]
        #expect(entry != nil)
        #expect(entry?.engine == "qwen3-tts")
        #expect(entry?.format == "bin")
        #expect(entry?.file == "qwen3-tts/1.7b/clone-prompt.bin")
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
        #expect(readBack.manifest.embeddingEntries == nil)
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

        // Verify embedding entry metadata for sample audio.
        let entry = readBack.manifest.embeddingEntries?["qwen3-tts-sample-audio"]
        #expect(entry != nil)
        #expect(entry?.format == "wav")
    }

    @Test("updateSampleAudio preserves existing clone prompt")
    func updateSampleAudioPreservesClonePrompt() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export with clone prompt (1.7B).
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

        // Both binaries should be present.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        #expect(readBack.embeddings["qwen3-tts/1.7b/clone-prompt.bin"] == cloneData)
        #expect(readBack.embeddings[VoxExporter.sampleAudioEmbeddingPath] == sampleData)

        // Both embedding entries should be present.
        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-1.7b"] != nil)
        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-sample-audio"] != nil)
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

        // Now update with a clone prompt (default 1.7B).
        let promptData = Data(repeating: 0xCD, count: 128)
        try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: promptData)

        // Verify the clone prompt is now present at model-specific path.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)
        let roundTripped = readBack.embeddings["qwen3-tts/1.7b/clone-prompt.bin"]
        #expect(roundTripped == promptData)

        // Verify embedding entry metadata.
        let entry = readBack.manifest.embeddingEntries?["qwen3-tts-1.7b"]
        #expect(entry != nil)
        #expect(entry?.engine == "qwen3-tts")
    }

    // MARK: - Multi-Model Tests

    @Test("updateClonePrompt with two models preserves both")
    func updateClonePromptMultiModel() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export with 1.7B clone prompt.
        let manifest = VoxExporter.buildManifest(
            name: "MultiModel",
            description: "Testing multi-model clone prompt coexistence.",
            voiceType: "designed"
        )
        let data1_7B = Data(repeating: 0xAA, count: 256)
        let voxURL = tempDir.appendingPathComponent("multi.vox")
        try VoxExporter.export(
            manifest: manifest,
            clonePromptData: data1_7B,
            clonePromptModelRepo: .base1_7B,
            to: voxURL
        )

        // Now add a 0.6B clone prompt.
        let data0_6B = Data(repeating: 0xBB, count: 128)
        try VoxExporter.updateClonePrompt(
            in: voxURL,
            clonePromptData: data0_6B,
            modelRepo: .base0_6B
        )

        // Verify BOTH clone prompts coexist.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)

        #expect(readBack.embeddings["qwen3-tts/1.7b/clone-prompt.bin"] == data1_7B)
        #expect(readBack.embeddings["qwen3-tts/0.6b/clone-prompt.bin"] == data0_6B)

        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-1.7b"] != nil)
        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-0.6b"] != nil)
    }

    @Test("updateClonePrompt preserves sample audio")
    func updateClonePromptPreservesSampleAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export with sample audio only.
        let manifest = VoxExporter.buildManifest(
            name: "AudioPreserve",
            description: "Testing that clone prompt update preserves sample audio.",
            voiceType: "designed"
        )
        let voxURL = tempDir.appendingPathComponent("audio-preserve.vox")
        try VoxExporter.export(manifest: manifest, to: voxURL)

        // Add sample audio first.
        let sampleData = Data(repeating: 0xDD, count: 200)
        try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

        // Now add a clone prompt.
        let promptData = Data(repeating: 0xEE, count: 100)
        try VoxExporter.updateClonePrompt(
            in: voxURL,
            clonePromptData: promptData,
            modelRepo: .base1_7B
        )

        // Verify both sample audio and clone prompt survive.
        let reader = VoxReader()
        let readBack = try reader.read(from: voxURL)

        #expect(readBack.embeddings[VoxExporter.sampleAudioEmbeddingPath] == sampleData)
        #expect(readBack.embeddings["qwen3-tts/1.7b/clone-prompt.bin"] == promptData)

        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-sample-audio"] != nil)
        #expect(readBack.manifest.embeddingEntries?["qwen3-tts-1.7b"] != nil)
    }
}
