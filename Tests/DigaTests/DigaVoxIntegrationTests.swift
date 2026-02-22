import Foundation
import Testing
import VoxFormat
@testable import SwiftVoxAlta
@testable import diga

@Suite("Diga VOX Integration Tests")
struct DigaVoxIntegrationTests {

    private func makeTempStore() -> VoiceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-vox-test-\(UUID().uuidString)", isDirectory: true)
        return VoiceStore(directory: tempDir)
    }

    private func cleanup(_ store: VoiceStore) {
        try? FileManager.default.removeItem(at: store.voicesDirectory)
    }

    // MARK: - Delete Cleanup

    @Test("deleteVoice removes .vox file alongside .cloneprompt")
    func deleteVoiceRemovesVoxFile() throws {
        let store = makeTempStore()
        defer { cleanup(store) }

        // Save a voice.
        let voice = StoredVoice(
            name: "deleteme",
            type: .designed,
            designDescription: "A voice that will be deleted."
        )
        try store.saveVoice(voice)

        // Create fake .vox and .cloneprompt files.
        let voxURL = store.voicesDirectory.appendingPathComponent("deleteme.vox")
        let promptURL = store.voicesDirectory.appendingPathComponent("deleteme.cloneprompt")
        try Data("fake vox".utf8).write(to: voxURL)
        try Data("fake prompt".utf8).write(to: promptURL)

        #expect(FileManager.default.fileExists(atPath: voxURL.path))
        #expect(FileManager.default.fileExists(atPath: promptURL.path))

        // Delete the voice.
        let deleted = try store.deleteVoice(name: "deleteme")
        #expect(deleted == true)

        // Both files should be gone.
        #expect(!FileManager.default.fileExists(atPath: voxURL.path))
        #expect(!FileManager.default.fileExists(atPath: promptURL.path))
    }

    @Test("deleteVoice with only .vox file (no .cloneprompt) still cleans up")
    func deleteVoiceRemovesVoxFileOnly() throws {
        let store = makeTempStore()
        defer { cleanup(store) }

        let voice = StoredVoice(name: "voxonly", type: .designed, designDescription: "Vox only voice")
        try store.saveVoice(voice)

        let voxURL = store.voicesDirectory.appendingPathComponent("voxonly.vox")
        try Data("fake vox".utf8).write(to: voxURL)

        #expect(FileManager.default.fileExists(atPath: voxURL.path))

        let deleted = try store.deleteVoice(name: "voxonly")
        #expect(deleted == true)
        #expect(!FileManager.default.fileExists(atPath: voxURL.path))
    }

    // MARK: - Export Round-Trip

    @Test("Update and import round-trips clone prompt data")
    func updateImportRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-roundtrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a .vox file using container-first API.
        let vox = VoxFile(name: "RoundTrip", description: "A voice for testing export and import.")
        vox.manifest.provenance = VoxManifest.Provenance(method: "designed", engine: "qwen3-tts")
        let voxURL = tempDir.appendingPathComponent("roundtrip.vox")
        try vox.write(to: voxURL)

        // Add a clone prompt via the update API.
        let promptData = Data(repeating: 0x42, count: 100)
        try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: promptData)

        let result = try VoxImporter.importVox(from: voxURL)
        #expect(result.name == "RoundTrip")
        #expect(result.description == "A voice for testing export and import.")
        #expect(result.method == "designed")
        #expect(result.clonePromptData == promptData)
    }
}
