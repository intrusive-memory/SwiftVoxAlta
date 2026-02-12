import Foundation

/// Built-in voice definitions shipped with diga.
///
/// Each built-in voice uses a Qwen3-TTS CustomVoice preset speaker.
/// These are professionally designed voices embedded in the CustomVoice model,
/// requiring no clone prompt extraction or voice design process.
enum BuiltinVoices {

    /// All built-in voice definitions.
    ///
    /// Maps diga voice names to CustomVoice speaker names and descriptions.
    private static let definitions: [(name: String, speaker: String, description: String)] = [
        // English speakers
        ("ryan", "ryan", "Dynamic male voice with strong rhythmic drive"),
        ("aiden", "aiden", "Sunny American male voice with clear midrange"),

        // Multilingual speakers (can speak English too)
        ("vivian", "vivian", "Bright, slightly edgy young female voice"),
        ("serena", "serena", "Warm, gentle young female voice"),
        ("anna", "ono_anna", "Playful Japanese female voice with light timbre"),
        ("sohee", "sohee", "Warm Korean female voice with rich emotion"),
    ]

    /// Returns all built-in voices as `StoredVoice` instances.
    static func all() -> [StoredVoice] {
        definitions.map { entry in
            StoredVoice(
                name: entry.name,
                type: .preset,
                designDescription: entry.description,
                clonePromptPath: entry.speaker,  // Store CustomVoice speaker name
                createdAt: Date(timeIntervalSinceReferenceDate: 0) // Fixed date for built-ins.
            )
        }
    }

    /// Returns a single built-in voice by name, or nil if not found.
    static func get(name: String) -> StoredVoice? {
        all().first { $0.name == name }
    }
}
