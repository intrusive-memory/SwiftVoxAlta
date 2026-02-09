//
//  CharacterProfile.swift
//  SwiftVoxAlta
//
//  Types representing analyzed character voice profiles and evidence extracted from screenplays.
//

import Foundation

/// Gender classification for a character, used for voice design targeting.
public enum Gender: String, Codable, Sendable {
    case male
    case female
    case nonBinary
    case unknown
}

/// An analyzed character profile derived from screenplay evidence, suitable for voice design.
///
/// `CharacterProfile` is the output of character analysis (via SwiftBruja LLM inference).
/// It contains the information needed to compose a Qwen3-TTS VoiceDesign description
/// that will generate a matching voice.
public struct CharacterProfile: Codable, Sendable {
    /// The character's name (normalized to uppercase).
    public let name: String

    /// The inferred gender of the character.
    public let gender: Gender

    /// A textual description of the character's approximate age range (e.g., "30s", "elderly", "young adult").
    public let ageRange: String

    /// A prose description of the character's personality and vocal qualities.
    public let description: String

    /// Specific voice traits inferred from dialogue and parentheticals
    /// (e.g., "gravelly", "warm", "clipped speech", "southern drawl").
    public let voiceTraits: [String]

    /// A concise summary combining all profile attributes, suitable for direct use
    /// as a Qwen3-TTS VoiceDesign prompt input.
    public let summary: String

    public init(
        name: String,
        gender: Gender,
        ageRange: String,
        description: String,
        voiceTraits: [String],
        summary: String
    ) {
        self.name = name
        self.gender = gender
        self.ageRange = ageRange
        self.description = description
        self.voiceTraits = voiceTraits
        self.summary = summary
    }
}

/// Raw evidence extracted from a screenplay for a single character.
///
/// `CharacterEvidence` collects all dialogue lines, parentheticals, scene headings,
/// and action mentions for a character. This evidence is fed to the LLM-based
/// `CharacterAnalyzer` to produce a `CharacterProfile`.
public struct CharacterEvidence: Codable, Sendable {
    /// The character's name (normalized to uppercase).
    public let characterName: String

    /// All dialogue lines spoken by this character.
    public var dialogueLines: [String]

    /// All parenthetical directions associated with this character's dialogue blocks.
    public var parentheticals: [String]

    /// Scene headings for scenes where this character appears (speaks).
    public var sceneHeadings: [String]

    /// Action lines that mention this character by name.
    public var actionMentions: [String]

    public init(
        characterName: String,
        dialogueLines: [String] = [],
        parentheticals: [String] = [],
        sceneHeadings: [String] = [],
        actionMentions: [String] = []
    ) {
        self.characterName = characterName
        self.dialogueLines = dialogueLines
        self.parentheticals = parentheticals
        self.sceneHeadings = sceneHeadings
        self.actionMentions = actionMentions
    }
}
