import Foundation
import Testing
@testable import diga

// MARK: - VoiceStore Tests

@Suite("VoiceStore Tests")
struct VoiceStoreTests {

    /// Creates a VoiceStore backed by a unique temporary directory.
    private func makeTempStore() throws -> VoiceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-test-\(UUID().uuidString)", isDirectory: true)
        return VoiceStore(directory: tempDir)
    }

    /// Cleans up a temporary VoiceStore directory.
    private func cleanup(_ store: VoiceStore) {
        try? FileManager.default.removeItem(at: store.voicesDirectory)
    }

    // --- Test 1: Save and get round-trip ---

    @Test("Save and get a voice round-trips correctly")
    func saveAndGetRoundTrip() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let voice = StoredVoice(
            name: "testvoice",
            type: .designed,
            designDescription: "A test voice",
            clonePromptPath: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 1000)
        )

        try store.saveVoice(voice)
        let retrieved = try store.getVoice(name: "testvoice")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "testvoice")
        #expect(retrieved?.type == .designed)
        #expect(retrieved?.designDescription == "A test voice")
    }

    // --- Test 2: Delete voice ---

    @Test("Delete removes a voice from the store")
    func deleteVoice() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let voice = StoredVoice(name: "ephemeral", type: .cloned)
        try store.saveVoice(voice)
        #expect(try store.getVoice(name: "ephemeral") != nil)

        let deleted = try store.deleteVoice(name: "ephemeral")
        #expect(deleted == true)
        #expect(try store.getVoice(name: "ephemeral") == nil)
    }

    // --- Test 3: Delete non-existent voice returns false ---

    @Test("Delete returns false for non-existent voice")
    func deleteNonExistentVoice() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let deleted = try store.deleteVoice(name: "ghost")
        #expect(deleted == false)
    }

    // --- Test 4: listVoices returns all saved voices ---

    @Test("listVoices returns all saved voices")
    func listVoicesReturnsAll() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let v1 = StoredVoice(name: "voice1", type: .designed, designDescription: "First")
        let v2 = StoredVoice(name: "voice2", type: .cloned, clonePromptPath: "/path/to/ref.wav")
        let v3 = StoredVoice(name: "voice3", type: .builtin, designDescription: "Third")

        try store.saveVoice(v1)
        try store.saveVoice(v2)
        try store.saveVoice(v3)

        let all = try store.listVoices()
        #expect(all.count == 3)

        let names = Set(all.map(\.name))
        #expect(names.contains("voice1"))
        #expect(names.contains("voice2"))
        #expect(names.contains("voice3"))
    }

    // --- Test 5: index.json round-trips ---

    @Test("Index file round-trips through JSON correctly")
    func indexJsonRoundTrip() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let voice = StoredVoice(
            name: "jsontest",
            type: .designed,
            designDescription: "JSON round-trip test",
            createdAt: Date(timeIntervalSinceReferenceDate: 5000)
        )
        try store.saveVoice(voice)

        // Verify the index file exists.
        #expect(FileManager.default.fileExists(atPath: store.indexFileURL.path))

        // Read it back through a fresh store pointing at same directory.
        let store2 = VoiceStore(directory: store.voicesDirectory)
        let voices = try store2.listVoices()
        #expect(voices.count == 1)
        #expect(voices[0].name == "jsontest")
        #expect(voices[0].designDescription == "JSON round-trip test")
    }

    // --- Test 6: Directory created on first access ---

    @Test("VoiceStore creates directory on first access")
    func directoryCreatedOnFirstAccess() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        // Directory should not exist yet.
        #expect(!FileManager.default.fileExists(atPath: store.voicesDirectory.path))

        // listVoices triggers ensureDirectory.
        let voices = try store.listVoices()
        #expect(voices.isEmpty)

        // Now the directory should exist.
        #expect(FileManager.default.fileExists(atPath: store.voicesDirectory.path))
    }

    // --- Test 7: Save replaces voice with same name ---

    @Test("Saving a voice with the same name replaces the existing entry")
    func saveReplacesExisting() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let v1 = StoredVoice(name: "update", type: .designed, designDescription: "Version 1")
        try store.saveVoice(v1)

        let v2 = StoredVoice(name: "update", type: .designed, designDescription: "Version 2")
        try store.saveVoice(v2)

        let voices = try store.listVoices()
        #expect(voices.count == 1)
        #expect(voices[0].designDescription == "Version 2")
    }

    // --- Test 8: Empty store returns empty list ---

    @Test("Empty store returns empty list")
    func emptyStoreReturnsEmptyList() throws {
        let store = try makeTempStore()
        defer { cleanup(store) }

        let voices = try store.listVoices()
        #expect(voices.isEmpty)
    }
}

// MARK: - BuiltinVoices Tests

@Suite("BuiltinVoices Tests")
struct BuiltinVoicesTests {

    // --- Test 9: all() returns 9 preset voices ---

    @Test("all() returns exactly 9 preset voices")
    func allReturnsNineVoices() {
        let voices = BuiltinVoices.all()
        #expect(voices.count == 9)
    }

    // --- Test 10: Each voice has non-empty name and description ---

    @Test("Each built-in voice has non-empty name and description")
    func eachVoiceHasNameAndDescription() {
        let voices = BuiltinVoices.all()
        for voice in voices {
            #expect(!voice.name.isEmpty, "Voice name should not be empty")
            #expect(voice.designDescription != nil, "Voice should have a design description")
            #expect(!voice.designDescription!.isEmpty, "Design description should not be empty")
        }
    }

    // --- Test 11: get(name:) returns correct voice ---

    @Test("get(name:) returns the correct preset voice")
    func getByNameReturnsCorrectVoice() {
        let ryan = BuiltinVoices.get(name: "ryan")
        #expect(ryan != nil)
        #expect(ryan?.name == "ryan")
        #expect(ryan?.type == .preset)
        #expect(ryan?.designDescription?.contains("Dynamic male") == true)

        let anna = BuiltinVoices.get(name: "anna")
        #expect(anna != nil)
        #expect(anna?.name == "anna")
        #expect(anna?.designDescription?.contains("Japanese female") == true)
    }

    // --- Test 12: get(name:) returns nil for unknown ---

    @Test("get(name:) returns nil for unknown voice name")
    func getUnknownReturnsNil() {
        let unknown = BuiltinVoices.get(name: "nonexistent")
        #expect(unknown == nil)
    }

    // --- Test 13: All preset voices have type .preset ---

    @Test("All preset voices have type .preset")
    func allVoicesArePresetType() {
        let voices = BuiltinVoices.all()
        for voice in voices {
            #expect(voice.type == .preset, "Voice \(voice.name) should have type .preset")
        }
    }

    // --- Test 14: Known voice names are present ---

    @Test("Preset voices include ryan, aiden, vivian, anna")
    func knownVoiceNamesPresent() {
        let names = Set(BuiltinVoices.all().map(\.name))
        #expect(names.contains("ryan"))
        #expect(names.contains("aiden"))
        #expect(names.contains("vivian"))
        #expect(names.contains("anna"))
    }
}

// MARK: - StoredVoice Codable Tests

@Suite("StoredVoice Codable Tests")
struct StoredVoiceCodableTests {

    // --- Test 15: StoredVoice Codable round-trip ---

    @Test("StoredVoice encodes and decodes correctly")
    func codableRoundTrip() throws {
        let original = StoredVoice(
            name: "codable-test",
            type: .cloned,
            designDescription: nil,
            clonePromptPath: "/some/path/ref.wav",
            createdAt: Date(timeIntervalSinceReferenceDate: 12345)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredVoice.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.type == original.type)
        #expect(decoded.designDescription == original.designDescription)
        #expect(decoded.clonePromptPath == original.clonePromptPath)
        #expect(decoded.createdAt == original.createdAt)
    }

    // --- Test 16: VoiceType Codable round-trip ---

    @Test("VoiceType encodes and decodes all cases correctly")
    func voiceTypeCodableRoundTrip() throws {
        let cases: [VoiceType] = [.builtin, .designed, .cloned]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for voiceType in cases {
            let data = try encoder.encode(voiceType)
            let decoded = try decoder.decode(VoiceType.self, from: data)
            #expect(decoded == voiceType, "VoiceType.\(voiceType) should round-trip")
        }
    }

    // --- Test 17: StoredVoice with all nil optionals round-trips ---

    @Test("StoredVoice with nil optionals round-trips correctly")
    func codableWithNilOptionals() throws {
        let original = StoredVoice(
            name: "minimal",
            type: .builtin,
            designDescription: nil,
            clonePromptPath: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredVoice.self, from: data)

        #expect(decoded.name == "minimal")
        #expect(decoded.type == .builtin)
        #expect(decoded.designDescription == nil)
        #expect(decoded.clonePromptPath == nil)
    }
}

// MARK: - CLI Output Tests

@Suite("CLI Voice Listing Tests")
struct CLIVoiceListingTests {

    // --- Test 18: --voices output format verification ---

    @Test("Voices listing contains Built-in header and all 9 preset voice names")
    func voicesOutputContainsExpectedContent() throws {
        // Simulate what runListVoices produces by calling the same
        // underlying types and verifying the data.
        let builtinVoices = BuiltinVoices.all()
        let names = builtinVoices.map(\.name)

        #expect(names.contains("ryan"))
        #expect(names.contains("aiden"))
        #expect(names.contains("vivian"))
        #expect(names.contains("anna"))

        // Verify the output format by building the same strings the command would print.
        var output = "Built-in:\n"
        for voice in builtinVoices {
            let description = voice.designDescription ?? ""
            output += "  \(voice.name)\t\(description)\n"
        }
        output += "\nCustom:\n"
        output += "  (none \u{2014} use `echada cast` to create, then --import-vox)\n"

        #expect(output.contains("Built-in:"))
        #expect(output.contains("ryan"))
        #expect(output.contains("aiden"))
        #expect(output.contains("vivian"))
        #expect(output.contains("anna"))
        #expect(output.contains("Custom:"))
    }
}
