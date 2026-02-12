//
//  VoiceDesignerTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoiceDesigner voice description composition.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("VoiceDesigner - composeVoiceDescription")
struct VoiceDesignerTests {

    // MARK: - Test Helpers

    private func makeProfile(
        name: String = "ELENA",
        gender: Gender = .female,
        ageRange: String = "30s",
        description: String = "A confident journalist.",
        voiceTraits: [String] = ["warm", "confident", "slightly husky"],
        summary: String = "A female journalist in her 30s with a warm, confident voice."
    ) -> CharacterProfile {
        CharacterProfile(
            name: name,
            gender: gender,
            ageRange: ageRange,
            description: description,
            voiceTraits: voiceTraits,
            summary: summary
        )
    }

    // MARK: - Basic Composition Tests

    @Test("Description contains gender word")
    func descriptionContainsGender() {
        let profile = makeProfile(gender: .female)
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("female"))
    }

    @Test("Description contains age range")
    func descriptionContainsAgeRange() {
        let profile = makeProfile(ageRange: "30s")
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("30s"))
    }

    @Test("Description contains summary")
    func descriptionContainsSummary() {
        let profile = makeProfile(summary: "A female journalist in her 30s with a warm, confident voice.")
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("A female journalist in her 30s"))
    }

    @Test("Description contains voice traits")
    func descriptionContainsVoiceTraits() {
        let profile = makeProfile(voiceTraits: ["warm", "confident", "slightly husky"])
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("warm"))
        #expect(description.contains("confident"))
        #expect(description.contains("slightly husky"))
        #expect(description.contains("Voice traits:"))
    }

    @Test("Description format matches expected pattern")
    func descriptionMatchesExpectedFormat() {
        let profile = makeProfile()
        let description = VoiceDesigner.composeVoiceDescription(from: profile)

        // Should start with "A female voice, 30s."
        #expect(description.hasPrefix("A female voice, 30s."))
        // Should contain "Voice traits:"
        #expect(description.contains("Voice traits:"))
    }

    // MARK: - Gender Variants

    @Test("Male gender produces 'male' in description")
    func maleGender() {
        let profile = makeProfile(gender: .male)
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("A male voice"))
    }

    @Test("Female gender produces 'female' in description")
    func femaleGender() {
        let profile = makeProfile(gender: .female)
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("A female voice"))
    }

    @Test("NonBinary gender produces 'non-binary' in description")
    func nonBinaryGender() {
        let profile = makeProfile(gender: .nonBinary)
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("A non-binary voice"))
    }

    @Test("Unknown gender produces 'neutral' in description")
    func unknownGender() {
        let profile = makeProfile(gender: .unknown)
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("A neutral voice"))
    }

    @Test("All Gender enum values produce valid descriptions")
    func allGenderValues() {
        for gender in [Gender.male, .female, .nonBinary, .unknown] {
            let profile = makeProfile(gender: gender)
            let description = VoiceDesigner.composeVoiceDescription(from: profile)
            #expect(!description.isEmpty, "Description for \(gender) should not be empty")
            #expect(description.hasPrefix("A "), "Description should start with 'A '")
        }
    }

    // MARK: - Empty Traits

    @Test("Empty traits array omits 'Voice traits:' section")
    func emptyTraitsOmitsSection() {
        let profile = makeProfile(voiceTraits: [])
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(!description.contains("Voice traits:"))
    }

    @Test("Empty traits array still includes gender, age, and summary")
    func emptyTraitsStillHasBasicInfo() {
        let profile = makeProfile(
            gender: .male,
            ageRange: "elderly",
            voiceTraits: [],
            summary: "An older gentleman with a deep, resonant voice."
        )
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("male"))
        #expect(description.contains("elderly"))
        #expect(description.contains("An older gentleman"))
    }

    // MARK: - Single Trait

    @Test("Single trait is included without extra commas")
    func singleTrait() {
        let profile = makeProfile(voiceTraits: ["gravelly"])
        let description = VoiceDesigner.composeVoiceDescription(from: profile)
        #expect(description.contains("Voice traits: gravelly."))
    }

    // MARK: - Sendable Conformance

    @Test("VoiceDesigner is accessible from non-isolated context")
    func sendableAccess() {
        // VoiceDesigner is an enum namespace — accessing its static methods
        // from any isolation domain should work (compile-time check).
        let profile = makeProfile()
        let _ = VoiceDesigner.composeVoiceDescription(from: profile)
    }
}
