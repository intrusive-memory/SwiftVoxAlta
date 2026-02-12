//
//  VoiceLock.swift
//  SwiftVoxAlta
//
//  A locked voice identity that can be serialized and reused for consistent TTS rendering.
//

import Foundation

/// A locked voice identity containing the clone prompt data needed to reproduce
/// a specific voice across multiple TTS generations.
///
/// `VoiceLock` is created after a user selects a voice candidate from the design process.
/// The clone prompt data (speaker embedding) is extracted from the selected candidate audio
/// and stored for future use. The app (Produciesta) persists this as `TypedDataStorage`
/// with mimeType `"application/x-clone-prompt"`.
public struct VoiceLock: Codable, Sendable {
    /// The character name this voice is locked to (normalized to uppercase).
    public let characterName: String

    /// The serialized clone prompt (speaker embedding) extracted from the selected voice candidate.
    public let clonePromptData: Data

    /// The voice design instruction text that was used to generate the original candidates.
    public let designInstruction: String

    /// The timestamp when this voice was locked.
    public let lockedAt: Date

    public init(
        characterName: String,
        clonePromptData: Data,
        designInstruction: String,
        lockedAt: Date = Date()
    ) {
        self.characterName = characterName
        self.clonePromptData = clonePromptData
        self.designInstruction = designInstruction
        self.lockedAt = lockedAt
    }
}
