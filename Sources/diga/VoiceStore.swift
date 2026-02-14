import Foundation

// MARK: - StoredVoice

/// The type of a stored voice.
enum VoiceType: String, Codable, Sendable {
    case builtin
    case designed
    case cloned
    case preset  // CustomVoice preset speaker (no clone prompt needed)
}

/// A voice entry stored in the VoiceStore index.
struct StoredVoice: Codable, Sendable, Equatable {
    let name: String
    let type: VoiceType
    let designDescription: String?
    let clonePromptPath: String?
    let createdAt: Date

    init(
        name: String,
        type: VoiceType,
        designDescription: String? = nil,
        clonePromptPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.type = type
        self.designDescription = designDescription
        self.clonePromptPath = clonePromptPath
        self.createdAt = createdAt
    }
}

// MARK: - VoiceStore

/// Manages persistence of voice definitions to disk.
///
/// Voices are stored in a JSON index file alongside optional clone prompt files.
/// The default store location is `~/.diga/voices/`, but a custom base directory
/// can be provided (useful for testing).
struct VoiceStore: Sendable {

    /// The directory where voices are stored.
    let voicesDirectory: URL

    /// The path to the JSON index file.
    var indexFileURL: URL {
        voicesDirectory.appendingPathComponent("index.json")
    }

    /// Creates a VoiceStore at the default location (`~/.diga/voices/`).
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.voicesDirectory = home
            .appendingPathComponent(".diga", isDirectory: true)
            .appendingPathComponent("voices", isDirectory: true)
    }

    /// Creates a VoiceStore at a custom base directory (for testing).
    init(directory: URL) {
        self.voicesDirectory = directory
    }

    // MARK: - Public API

    /// Returns all voices stored in the index.
    func listVoices() throws -> [StoredVoice] {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: indexFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([StoredVoice].self, from: data)
    }

    /// Returns a single voice by name, or nil if not found.
    func getVoice(name: String) throws -> StoredVoice? {
        let voices = try listVoices()
        return voices.first { $0.name == name }
    }

    /// Saves a voice to the index. If a voice with the same name exists, it is replaced.
    func saveVoice(_ voice: StoredVoice) throws {
        try ensureDirectory()
        var voices = try listVoices()
        voices.removeAll { $0.name == voice.name }
        voices.append(voice)
        try writeIndex(voices)
    }

    /// Deletes a voice by name. Returns true if the voice was found and removed.
    @discardableResult
    func deleteVoice(name: String) throws -> Bool {
        var voices = try listVoices()
        let before = voices.count
        voices.removeAll { $0.name == name }
        if voices.count < before {
            try writeIndex(voices)
            // Also remove any associated clone prompt file.
            let promptURL = voicesDirectory.appendingPathComponent("\(name).cloneprompt")
            if FileManager.default.fileExists(atPath: promptURL.path) {
                try FileManager.default.removeItem(at: promptURL)
            }
            return true
        }
        return false
    }

    // MARK: - Private

    /// Ensures the voices directory exists, creating it if necessary.
    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: voicesDirectory.path) {
            try fm.createDirectory(at: voicesDirectory, withIntermediateDirectories: true)
        }
    }

    /// Writes the voice list to the index file.
    private func writeIndex(_ voices: [StoredVoice]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(voices)
        try data.write(to: indexFileURL, options: .atomic)
    }
}
