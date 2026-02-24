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
        consent: String? = nil,
        source: [String]? = nil,
        clonePromptData: Data? = nil,
        includeReference: Bool = false,
        in directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let vox = VoxFile(name: name, description: description)
        vox.manifest.provenance = VoxManifest.Provenance(
            method: method,
            engine: "qwen3-tts",
            consent: consent,
            source: source
        )

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
            consent: "self",
            source: ["reference/ref-audio.wav"],
            includeReference: true,
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

    @Test("importVox recognizes synthesized method")
    func importSynthesizedMethod() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }

        let voxURL = try createTestVox(
            name: "SynthesizedVoice",
            description: "A synthesized voice from model generation.",
            method: "synthesized",
            in: tempDir
        )

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.method == "synthesized")
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

    // MARK: - Multi-Model Disambiguation Regression Tests

    /// Regression test: when a .vox has both clone prompts AND sample audio for
    /// multiple models, importVox must return the clone prompt — not the sample
    /// audio WAV data. Prior to the fix, embeddingData(for:) used substring
    /// matching that could non-deterministically return sample audio instead.
    @Test("importVox returns clone prompt, not sample audio, for multi-model .vox")
    func importMultiModelReturnsClonePromptNotSampleAudio() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let clonePrompt06b = Data([0xC0, 0x06, 0xBB])
        let sampleAudio06b = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x06])  // RIFF header
        let clonePrompt17b = Data([0xC1, 0x07, 0xBB])
        let sampleAudio17b = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x17])  // RIFF header

        let vox = VoxFile(name: "MultiModel", description: "A multi-model test voice for disambiguation.")
        vox.manifest.provenance = VoxManifest.Provenance(method: "synthesized", engine: "qwen3-tts")

        // Add both models' clone prompts and sample audio
        try VoxExporter.addClonePrompt(to: vox, data: clonePrompt06b, modelRepo: .base0_6B)
        try VoxExporter.addSampleAudio(to: vox, data: sampleAudio06b, modelRepo: .base0_6B)
        try VoxExporter.addClonePrompt(to: vox, data: clonePrompt17b, modelRepo: .base1_7B)
        try VoxExporter.addSampleAudio(to: vox, data: sampleAudio17b, modelRepo: .base1_7B)

        let voxURL = tempDir.appendingPathComponent("multi-model.vox")
        try vox.write(to: voxURL)

        // Import with default 1.7b query
        let result = try VoxImporter.importVox(from: voxURL, modelQuery: "1.7b")
        #expect(result.clonePromptData == clonePrompt17b,
            "clonePromptData must be the 1.7b clone prompt, not sample audio")
        #expect(result.sampleAudioData == sampleAudio17b,
            "sampleAudioData must be the 1.7b sample audio")

        // Import with 0.6b query
        let result06b = try VoxImporter.importVox(from: voxURL, modelQuery: "0.6b")
        #expect(result06b.clonePromptData == clonePrompt06b,
            "clonePromptData must be the 0.6b clone prompt, not sample audio")
        #expect(result06b.sampleAudioData == sampleAudio06b,
            "sampleAudioData must be the 0.6b sample audio")
    }

    /// Stress test: run the multi-model import many times to catch non-deterministic
    /// dictionary ordering bugs.
    @Test("importVox clone prompt disambiguation is deterministic across iterations")
    func importMultiModelDeterministic() throws {
        let tempDir = makeTempDir()
        defer { cleanup(tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let clonePromptData = Data([0xDE, 0xAD])
        let sampleAudioData = Data([0x52, 0x49, 0x46, 0x46, 0xBE, 0xEF])

        let vox = VoxFile(name: "StressTest", description: "A voice for determinism stress testing.")
        try VoxExporter.addClonePrompt(to: vox, data: clonePromptData, modelRepo: .base1_7B)
        try VoxExporter.addSampleAudio(to: vox, data: sampleAudioData, modelRepo: .base1_7B)

        let voxURL = tempDir.appendingPathComponent("stress.vox")
        try vox.write(to: voxURL)

        for _ in 0..<50 {
            let result = try VoxImporter.importVox(from: voxURL)
            #expect(result.clonePromptData == clonePromptData,
                "clonePromptData must always be the clone prompt, never sample audio")
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
