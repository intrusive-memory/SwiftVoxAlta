import Foundation

/// Built-in voice definitions shipped with diga.
///
/// Each built-in voice uses macOS `say` to generate reference audio on first use,
/// then clones that voice using Qwen3-TTS Base model. This is much faster than
/// VoiceDesign (seconds vs minutes) while still producing good quality.
enum BuiltinVoices {

    /// All built-in voice definitions.
    ///
    /// Maps diga voice names to macOS `say` voices and descriptions.
    /// Reference audio is auto-generated on first use.
    private static let definitions: [(name: String, description: String, sayVoice: String)] = [
        ("alex", "Male, American, warm baritone, conversational", "Alex"),
        ("samantha", "Female, American, clear soprano, professional", "Samantha"),
        ("daniel", "Male, British, deep tenor, authoritative", "Daniel"),
        ("karen", "Female, Australian, alto, friendly", "Karen"),
    ]

    /// Returns all built-in voices as `StoredVoice` instances.
    static func all() -> [StoredVoice] {
        definitions.map { entry in
            StoredVoice(
                name: entry.name,
                type: .cloned,  // Changed from .builtin to .cloned
                designDescription: entry.description,
                clonePromptPath: "\(entry.name)-reference.wav",  // Reference audio filename
                createdAt: Date(timeIntervalSinceReferenceDate: 0) // Fixed date for built-ins.
            )
        }
    }

    /// Returns a single built-in voice by name, or nil if not found.
    static func get(name: String) -> StoredVoice? {
        all().first { $0.name == name }
    }
}
