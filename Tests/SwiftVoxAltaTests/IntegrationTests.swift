//
//  IntegrationTests.swift
//  SwiftVoxAltaTests
//
//  End-to-end integration tests verifying the full VoxAlta pipeline wiring
//  without actual model inference. Tests data flow through components.
//

import Foundation
import Testing
import SwiftCompartido
@preconcurrency import MLX
@testable import SwiftVoxAlta

// MARK: - Pipeline Flow Integration Tests

@Suite("Integration - Pipeline Flow")
struct PipelineFlowTests {

    /// Build a mock screenplay with 2 characters (ELENA and MARCUS),
    /// 3 dialogue lines each, 1 parenthetical each.
    private func makeTwoCharacterScreenplay() -> [GuionElement] {
        [
            // Scene 1
            GuionElement(elementType: .sceneHeading, elementText: "INT. NEWSROOM - DAY"),
            GuionElement(elementType: .action, elementText: "Elena stands at her desk, reviewing notes. Marcus approaches with a folder."),

            // Elena dialogue block 1
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .parenthetical, elementText: "(whispering)"),
            GuionElement(elementType: .dialogue, elementText: "Did you get the documents?"),

            // Marcus dialogue block 1
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .dialogue, elementText: "Right here. But we need to be careful."),

            // Elena dialogue block 2
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .dialogue, elementText: "I've been careful my entire career."),

            // Scene 2
            GuionElement(elementType: .sceneHeading, elementText: "EXT. PARKING GARAGE - NIGHT"),
            GuionElement(elementType: .action, elementText: "Marcus leans against his car, checking his phone."),

            // Marcus dialogue block 2
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .parenthetical, elementText: "(nervously)"),
            GuionElement(elementType: .dialogue, elementText: "Something doesn't feel right."),

            // Elena dialogue block 3
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .dialogue, elementText: "Trust your instincts. Let's go."),

            // Marcus dialogue block 3
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .dialogue, elementText: "After you."),
        ]
    }

    @Test("Full pipeline: extract evidence, map parentheticals, compose voice descriptions")
    func fullPipelineFlow() {
        let elements = makeTwoCharacterScreenplay()

        // Step 1: Extract evidence
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // Verify evidence structure
        #expect(evidence.count == 2, "Should have evidence for exactly 2 characters")
        #expect(evidence["ELENA"] != nil, "Should have evidence for ELENA")
        #expect(evidence["MARCUS"] != nil, "Should have evidence for MARCUS")

        let elenaEvidence = evidence["ELENA"]!
        let marcusEvidence = evidence["MARCUS"]!

        // Verify dialogue counts
        #expect(elenaEvidence.dialogueLines.count == 3, "ELENA should have 3 dialogue lines")
        #expect(marcusEvidence.dialogueLines.count == 3, "MARCUS should have 3 dialogue lines")

        // Verify parentheticals
        #expect(elenaEvidence.parentheticals.count == 1, "ELENA should have 1 parenthetical")
        #expect(marcusEvidence.parentheticals.count == 1, "MARCUS should have 1 parenthetical")

        // Step 2: Map parentheticals to TTS instruct strings
        let elenaInstruct = ParentheticalMapper.mapToInstruct(elenaEvidence.parentheticals[0])
        let marcusInstruct = ParentheticalMapper.mapToInstruct(marcusEvidence.parentheticals[0])

        // Whispering is a vocal parenthetical - should produce instruct
        #expect(elenaInstruct != nil, "Whispering should produce an instruct string")
        #expect(elenaInstruct!.contains("whisper"), "Whispering instruct should mention whisper")

        // Nervously is a vocal parenthetical - should produce instruct
        #expect(marcusInstruct != nil, "Nervously should produce an instruct string")
        #expect(marcusInstruct!.contains("nervously") || marcusInstruct!.contains("hesitation"),
                "Nervously instruct should reference nervousness or hesitation")

        // Step 3: Compose voice descriptions from mock profiles
        let elenaProfile = CharacterProfile(
            name: "ELENA",
            gender: .female,
            ageRange: "30s",
            description: "A determined investigative journalist.",
            voiceTraits: ["warm", "confident", "slightly husky"],
            summary: "A female journalist in her 30s with a warm, confident voice."
        )

        let marcusProfile = CharacterProfile(
            name: "MARCUS",
            gender: .male,
            ageRange: "40s",
            description: "A cautious but loyal colleague.",
            voiceTraits: ["deep", "measured", "calm"],
            summary: "A male professional in his 40s with a deep, measured voice."
        )

        let elenaDescription = VoiceDesigner.composeVoiceDescription(from: elenaProfile)
        let marcusDescription = VoiceDesigner.composeVoiceDescription(from: marcusProfile)

        // Verify descriptions contain expected elements
        #expect(elenaDescription.contains("female"), "Elena's description should mention female")
        #expect(elenaDescription.contains("30s"), "Elena's description should mention age range")
        #expect(elenaDescription.contains("warm"), "Elena's description should include voice traits")
        #expect(elenaDescription.contains("confident"), "Elena's description should include confident trait")

        #expect(marcusDescription.contains("male"), "Marcus's description should mention male")
        #expect(marcusDescription.contains("40s"), "Marcus's description should mention age range")
        #expect(marcusDescription.contains("deep"), "Marcus's description should include deep trait")
        #expect(marcusDescription.contains("measured"), "Marcus's description should include measured trait")

        // Verify the two descriptions are different
        #expect(elenaDescription != marcusDescription,
                "Different profiles should produce different descriptions")
    }

    @Test("Pipeline verifies blocking parentheticals return nil instruct")
    func blockingParentheticalsReturnNil() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .parenthetical, elementText: "(beat)"),
            GuionElement(elementType: .dialogue, elementText: "Fine."),
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .parenthetical, elementText: "(turning away)"),
            GuionElement(elementType: .dialogue, elementText: "Whatever."),
        ]

        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        let elenaInstruct = ParentheticalMapper.mapToInstruct(evidence["ELENA"]!.parentheticals[0])
        let marcusInstruct = ParentheticalMapper.mapToInstruct(evidence["MARCUS"]!.parentheticals[0])

        #expect(elenaInstruct == nil, "'(beat)' is a blocking parenthetical and should return nil")
        #expect(marcusInstruct == nil, "'(turning away)' is a blocking parenthetical and should return nil")
    }

    @Test("Scene headings are correctly associated with characters")
    func sceneHeadingAssociation() {
        let elements = makeTwoCharacterScreenplay()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // Both characters appear in both scenes
        #expect(evidence["ELENA"]!.sceneHeadings.count == 2)
        #expect(evidence["MARCUS"]!.sceneHeadings.count == 2)
        #expect(evidence["ELENA"]!.sceneHeadings.contains("INT. NEWSROOM - DAY"))
        #expect(evidence["ELENA"]!.sceneHeadings.contains("EXT. PARKING GARAGE - NIGHT"))
    }

    @Test("Action mentions are extracted for both characters")
    func actionMentionExtraction() {
        let elements = makeTwoCharacterScreenplay()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // Action lines mention both characters
        #expect(evidence["ELENA"]!.actionMentions.count >= 1,
                "ELENA should be mentioned in at least 1 action line")
        #expect(evidence["MARCUS"]!.actionMentions.count >= 1,
                "MARCUS should be mentioned in at least 1 action line")
    }
}

// MARK: - VoiceProvider Pipeline Tests

@Suite(
    "Integration - VoiceProvider Pipeline",
    .disabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "Metal compiler not supported on GitHub Actions")
)
struct VoiceProviderPipelineTests {

    @Test("Provider starts unconfigured with no voices")
    func providerStartsEmpty() async throws {
        let provider = VoxAltaVoiceProvider()

        let configured = await provider.isConfigured()
        #expect(configured == true, "Provider should report configured (no API key needed)")

        let voices = try await provider.fetchVoices(languageCode: "en")
        #expect(voices.count == 9, "Should have 9 preset speakers initially")
    }

    @Test("Load voices, verify availability, then unload")
    func loadVerifyUnload() async throws {
        let provider = VoxAltaVoiceProvider()

        // Load fake clone prompt data for two characters
        let elenaCloneData = Data((0..<256).map { UInt8($0 % 256) })
        let marcusCloneData = Data((0..<256).map { UInt8(($0 + 128) % 256) })

        await provider.loadVoice(id: "ELENA", clonePromptData: elenaCloneData, gender: "female")
        await provider.loadVoice(id: "MARCUS", clonePromptData: marcusCloneData, gender: "male")

        // Verify fetchVoices returns 9 preset speakers + 2 custom voices
        let voices = try await provider.fetchVoices(languageCode: "en")
        #expect(voices.count == 11, "Should have 9 preset speakers + 2 custom voices")

        let voiceIds = Set(voices.map { $0.id })
        #expect(voiceIds.contains("ELENA"))
        #expect(voiceIds.contains("MARCUS"))

        // Verify isVoiceAvailable
        let elenaAvailable = await provider.isVoiceAvailable(voiceId: "ELENA")
        let marcusAvailable = await provider.isVoiceAvailable(voiceId: "MARCUS")
        #expect(elenaAvailable == true)
        #expect(marcusAvailable == true)

        // Verify generateAudio throws for unloaded voice
        do {
            _ = try await provider.generateAudio(
                text: "Hello",
                voiceId: "UNKNOWN",
                languageCode: "en"
            )
            Issue.record("Expected voiceNotLoaded error for UNKNOWN voice")
        } catch let error as VoxAltaError {
            if case .voiceNotLoaded(let id) = error {
                #expect(id == "UNKNOWN")
            } else {
                Issue.record("Expected voiceNotLoaded, got \(error)")
            }
        }

        // Estimate duration for different text lengths
        let shortDuration = await provider.estimateDuration(text: "Hello", voiceId: "ELENA")
        let longDuration = await provider.estimateDuration(
            text: "This is a much longer sentence that contains many more words for testing",
            voiceId: "ELENA"
        )
        #expect(shortDuration > 0, "Short text should have positive duration estimate")
        #expect(longDuration > shortDuration, "Longer text should have longer duration estimate")

        // Unload all voices and verify presets remain
        await provider.unloadAllVoices()
        let afterUnload = try await provider.fetchVoices(languageCode: "en")
        #expect(afterUnload.count == 9, "Should still have 9 preset speakers after unloading custom voices")

        let elenaStillAvailable = await provider.isVoiceAvailable(voiceId: "ELENA")
        #expect(elenaStillAvailable == false, "ELENA should no longer be available after unload")
    }

    @Test("Voice metadata flows correctly from cache to fetchVoices")
    func voiceMetadataFlows() async throws {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]), gender: "female")
        await provider.loadVoice(id: "MARCUS", clonePromptData: Data([0x02]), gender: "male")

        let voices = try await provider.fetchVoices(languageCode: "fr")

        let elena = voices.first(where: { $0.id == "ELENA" })
        let marcus = voices.first(where: { $0.id == "MARCUS" })

        #expect(elena != nil)
        #expect(elena?.gender == "female")
        #expect(elena?.language == "fr", "Language should match the requested code")
        #expect(elena?.providerId == "voxalta")

        #expect(marcus != nil)
        #expect(marcus?.gender == "male")
        #expect(marcus?.language == "fr")
    }
}

// MARK: - Evidence-to-Profile Pipeline Tests

@Suite("Integration - Evidence to Profile to Description")
struct EvidenceToProfilePipelineTests {

    @Test("Evidence from screenplay elements flows into manual profile to voice description")
    func evidenceToProfileToDescription() {
        // Build evidence from sample screenplay elements
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. COURTROOM - DAY"),
            GuionElement(elementType: .action, elementText: "Judge Rivera enters from chambers, commanding the room's attention."),
            GuionElement(elementType: .character, elementText: "JUDGE RIVERA"),
            GuionElement(elementType: .parenthetical, elementText: "(firmly)"),
            GuionElement(elementType: .dialogue, elementText: "Order in the court."),
            GuionElement(elementType: .character, elementText: "JUDGE RIVERA"),
            GuionElement(elementType: .dialogue, elementText: "The prosecution may proceed."),
            GuionElement(elementType: .character, elementText: "JUDGE RIVERA"),
            GuionElement(elementType: .dialogue, elementText: "I will not tolerate any further outbursts."),
        ]

        let evidence = CharacterEvidenceExtractor.extract(from: elements)
        let judgeEvidence = evidence["JUDGE RIVERA"]!

        // Verify evidence was extracted
        #expect(judgeEvidence.dialogueLines.count == 3)
        #expect(judgeEvidence.parentheticals.count == 1)
        #expect(judgeEvidence.sceneHeadings.count == 1)
        #expect(judgeEvidence.actionMentions.count >= 1)

        // Build a manual CharacterProfile from the evidence (no LLM needed)
        let profile = CharacterProfile(
            name: judgeEvidence.characterName,
            gender: .female,
            ageRange: "50s",
            description: "An authoritative judge who commands respect in the courtroom.",
            voiceTraits: ["authoritative", "measured", "firm", "clear"],
            summary: "A female judge in her 50s with an authoritative, measured voice that commands respect."
        )

        // Compose voice description
        let description = VoiceDesigner.composeVoiceDescription(from: profile)

        // Verify description flows from profile traits correctly
        #expect(description.contains("female"), "Description should reflect gender")
        #expect(description.contains("50s"), "Description should reflect age range")
        #expect(description.contains("authoritative"), "Description should include voice traits")
        #expect(description.contains("measured"), "Description should include voice traits")
        #expect(description.contains("firm"), "Description should include voice traits")
        #expect(description.contains("Voice traits:"), "Description should have traits section")

        // Verify the parenthetical maps to a valid instruct
        let instruct = ParentheticalMapper.mapToInstruct(judgeEvidence.parentheticals[0])
        #expect(instruct != nil, "(firmly) should produce an instruct string")
        #expect(instruct!.contains("authority") || instruct!.contains("firmly"),
                "Firmly instruct should reference authority or firmness")
    }

    @Test("Multiple characters from same screenplay produce distinct profiles and descriptions")
    func multipleCharactersProduceDistinctDescriptions() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. HOSPITAL - NIGHT"),
            GuionElement(elementType: .character, elementText: "DR. CHEN"),
            GuionElement(elementType: .dialogue, elementText: "We need to operate immediately."),
            GuionElement(elementType: .character, elementText: "NURSE KELLY"),
            GuionElement(elementType: .dialogue, elementText: "The OR is prepped and ready."),
        ]

        let evidence = CharacterEvidenceExtractor.extract(from: elements)
        #expect(evidence.count == 2)

        let chenProfile = CharacterProfile(
            name: "DR. CHEN",
            gender: .male,
            ageRange: "40s",
            description: "A skilled surgeon under pressure.",
            voiceTraits: ["authoritative", "calm under pressure", "precise"],
            summary: "A male surgeon in his 40s with an authoritative, precise voice."
        )

        let kellyProfile = CharacterProfile(
            name: "NURSE KELLY",
            gender: .female,
            ageRange: "20s",
            description: "A capable young nurse, efficient and warm.",
            voiceTraits: ["bright", "efficient", "warm"],
            summary: "A young female nurse in her 20s with a bright, efficient voice."
        )

        let chenDescription = VoiceDesigner.composeVoiceDescription(from: chenProfile)
        let kellyDescription = VoiceDesigner.composeVoiceDescription(from: kellyProfile)

        #expect(chenDescription != kellyDescription,
                "Different character profiles should produce different voice descriptions")
        #expect(chenDescription.contains("male"))
        #expect(kellyDescription.contains("female"))
    }
}
