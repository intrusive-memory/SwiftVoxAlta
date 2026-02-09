import Foundation

/// Built-in voice definitions shipped with diga.
///
/// Each built-in voice is a text description intended for Qwen3-TTS VoiceDesign.
/// On first use, the description is fed to VoiceDesign to generate a clone prompt
/// which is then cached locally.
enum BuiltinVoices {

    /// All built-in voice definitions.
    private static let definitions: [(name: String, description: String)] = [
        ("alex", "Male, American, warm baritone, conversational"),
        ("samantha", "Female, American, clear soprano, professional"),
        ("daniel", "Male, British, deep tenor, authoritative"),
        ("karen", "Female, Australian, alto, friendly"),
    ]

    /// Returns all built-in voices as `StoredVoice` instances.
    static func all() -> [StoredVoice] {
        definitions.map { entry in
            StoredVoice(
                name: entry.name,
                type: .builtin,
                designDescription: entry.description,
                clonePromptPath: nil,
                createdAt: Date(timeIntervalSinceReferenceDate: 0) // Fixed date for built-ins.
            )
        }
    }

    /// Returns a single built-in voice by name, or nil if not found.
    static func get(name: String) -> StoredVoice? {
        all().first { $0.name == name }
    }
}
