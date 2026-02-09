//
//  TypeTests.swift
//  SwiftVoxAltaTests
//
//  Tests Codable round-trips for CharacterProfile, CharacterEvidence, VoiceLock, VoxAltaConfig.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("Type Codable Round-Trip Tests")
struct TypeTests {

    // MARK: - CharacterProfile

    @Test("CharacterProfile round-trips through JSON encoding and decoding")
    func characterProfileCodable() throws {
        let profile = CharacterProfile(
            name: "ELENA",
            gender: .female,
            ageRange: "30s",
            description: "A confident journalist with a warm but direct manner of speaking.",
            voiceTraits: ["warm", "confident", "slightly husky"],
            summary: "A female journalist in her 30s with a warm, confident, slightly husky voice."
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CharacterProfile.self, from: data)

        #expect(decoded.name == profile.name)
        #expect(decoded.gender == profile.gender)
        #expect(decoded.ageRange == profile.ageRange)
        #expect(decoded.description == profile.description)
        #expect(decoded.voiceTraits == profile.voiceTraits)
        #expect(decoded.summary == profile.summary)
    }

    @Test("All Gender cases round-trip through Codable")
    func genderCodable() throws {
        for gender in [Gender.male, .female, .nonBinary, .unknown] {
            let data = try JSONEncoder().encode(gender)
            let decoded = try JSONDecoder().decode(Gender.self, from: data)
            #expect(decoded == gender)
        }
    }

    // MARK: - CharacterEvidence

    @Test("CharacterEvidence round-trips through JSON encoding and decoding")
    func characterEvidenceCodable() throws {
        let evidence = CharacterEvidence(
            characterName: "MARCUS",
            dialogueLines: ["Hello there.", "I have a plan.", "Trust me on this."],
            parentheticals: ["(whispering)", "(to himself)"],
            sceneHeadings: ["INT. OFFICE - DAY", "EXT. PARK - NIGHT"],
            actionMentions: ["Marcus enters the room.", "He reaches for the phone."]
        )

        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(CharacterEvidence.self, from: data)

        #expect(decoded.characterName == evidence.characterName)
        #expect(decoded.dialogueLines == evidence.dialogueLines)
        #expect(decoded.parentheticals == evidence.parentheticals)
        #expect(decoded.sceneHeadings == evidence.sceneHeadings)
        #expect(decoded.actionMentions == evidence.actionMentions)
    }

    @Test("CharacterEvidence with empty arrays round-trips correctly")
    func characterEvidenceEmptyCodable() throws {
        let evidence = CharacterEvidence(characterName: "GHOST")

        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(CharacterEvidence.self, from: data)

        #expect(decoded.characterName == "GHOST")
        #expect(decoded.dialogueLines.isEmpty)
        #expect(decoded.parentheticals.isEmpty)
        #expect(decoded.sceneHeadings.isEmpty)
        #expect(decoded.actionMentions.isEmpty)
    }

    // MARK: - VoiceLock

    @Test("VoiceLock round-trips through JSON encoding and decoding")
    func voiceLockCodable() throws {
        let cloneData = Data([0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD])
        let lockedDate = Date(timeIntervalSince1970: 1700000000)

        let voiceLock = VoiceLock(
            characterName: "ELENA",
            clonePromptData: cloneData,
            designInstruction: "A warm female voice in her 30s with a slightly husky quality.",
            lockedAt: lockedDate
        )

        let data = try JSONEncoder().encode(voiceLock)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: data)

        #expect(decoded.characterName == voiceLock.characterName)
        #expect(decoded.clonePromptData == voiceLock.clonePromptData)
        #expect(decoded.designInstruction == voiceLock.designInstruction)
        #expect(decoded.lockedAt == voiceLock.lockedAt)
    }

    // MARK: - VoxAltaConfig

    @Test("VoxAltaConfig round-trips through JSON encoding and decoding")
    func voxAltaConfigCodable() throws {
        let config = VoxAltaConfig(
            designModel: "mlx-community/Qwen3-TTS-12Hz-VoiceDesign-1.7B-bf16",
            renderModel: "mlx-community/Qwen3-TTS-12Hz-Base-1.7B-bf16",
            analysisModel: "mlx-community/Qwen3-4B-4bit",
            candidateCount: 5,
            outputFormat: .m4a
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VoxAltaConfig.self, from: data)

        #expect(decoded.designModel == config.designModel)
        #expect(decoded.renderModel == config.renderModel)
        #expect(decoded.analysisModel == config.analysisModel)
        #expect(decoded.candidateCount == config.candidateCount)
        #expect(decoded.outputFormat == config.outputFormat)
    }

    @Test("VoxAltaConfig default has sensible values")
    func voxAltaConfigDefault() {
        let config = VoxAltaConfig.default

        #expect(!config.designModel.isEmpty)
        #expect(!config.renderModel.isEmpty)
        #expect(!config.analysisModel.isEmpty)
        #expect(config.candidateCount > 0)
        #expect(config.outputFormat == .wav)
    }

    @Test("All AudioOutputFormat cases round-trip through Codable")
    func audioOutputFormatCodable() throws {
        for format in [AudioOutputFormat.wav, .aiff, .m4a] {
            let data = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(AudioOutputFormat.self, from: data)
            #expect(decoded == format)
        }
    }
}
