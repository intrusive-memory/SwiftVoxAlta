//
//  CharacterEvidenceExtractorTests.swift
//  SwiftVoxAltaTests
//
//  Tests character evidence extraction from mock screenplay elements.
//

import Foundation
import Testing
import SwiftCompartido
@testable import SwiftVoxAlta

@Suite("CharacterEvidenceExtractor Tests")
struct CharacterEvidenceExtractorTests {

    /// Build a mock screenplay with 2 characters, 3 dialogue lines each, and 1 parenthetical each.
    private func makeMockElements() -> [GuionElement] {
        [
            // Scene 1
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .action, elementText: "Elena walks into the room and sits down."),

            // Elena's first dialogue block
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .dialogue, elementText: "We need to talk about the plan."),

            // Marcus's first dialogue block
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .parenthetical, elementText: "(leaning forward)"),
            GuionElement(elementType: .dialogue, elementText: "I'm listening."),

            // Elena's second dialogue block
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .parenthetical, elementText: "(whispering)"),
            GuionElement(elementType: .dialogue, elementText: "They're watching us."),

            // Scene 2
            GuionElement(elementType: .sceneHeading, elementText: "EXT. PARK - NIGHT"),
            GuionElement(elementType: .action, elementText: "Marcus sits on a bench, staring at the sky."),

            // Marcus's second dialogue block
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .dialogue, elementText: "I wonder if she's right."),

            // Elena's third dialogue block
            GuionElement(elementType: .character, elementText: "ELENA"),
            GuionElement(elementType: .dialogue, elementText: "I'm always right."),

            // Marcus's third dialogue block
            GuionElement(elementType: .character, elementText: "MARCUS"),
            GuionElement(elementType: .dialogue, elementText: "That's what worries me."),
        ]
    }

    @Test("Extracts evidence for both characters")
    func extractsBothCharacters() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        #expect(evidence.count == 2)
        #expect(evidence["ELENA"] != nil)
        #expect(evidence["MARCUS"] != nil)
    }

    @Test("Each character has 3 dialogue lines")
    func correctDialogueCount() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        #expect(evidence["ELENA"]!.dialogueLines.count == 3)
        #expect(evidence["MARCUS"]!.dialogueLines.count == 3)
    }

    @Test("Dialogue lines contain correct text")
    func correctDialogueContent() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        #expect(evidence["ELENA"]!.dialogueLines[0] == "We need to talk about the plan.")
        #expect(evidence["ELENA"]!.dialogueLines[1] == "They're watching us.")
        #expect(evidence["ELENA"]!.dialogueLines[2] == "I'm always right.")

        #expect(evidence["MARCUS"]!.dialogueLines[0] == "I'm listening.")
        #expect(evidence["MARCUS"]!.dialogueLines[1] == "I wonder if she's right.")
        #expect(evidence["MARCUS"]!.dialogueLines[2] == "That's what worries me.")
    }

    @Test("Parentheticals are collected correctly")
    func correctParentheticals() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        #expect(evidence["ELENA"]!.parentheticals.count == 1)
        #expect(evidence["ELENA"]!.parentheticals[0] == "(whispering)")

        #expect(evidence["MARCUS"]!.parentheticals.count == 1)
        #expect(evidence["MARCUS"]!.parentheticals[0] == "(leaning forward)")
    }

    @Test("Scene headings are tracked per character")
    func correctSceneHeadings() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // Elena appears in both scenes
        #expect(evidence["ELENA"]!.sceneHeadings.count == 2)
        #expect(evidence["ELENA"]!.sceneHeadings.contains("INT. OFFICE - DAY"))
        #expect(evidence["ELENA"]!.sceneHeadings.contains("EXT. PARK - NIGHT"))

        // Marcus also appears in both scenes
        #expect(evidence["MARCUS"]!.sceneHeadings.count == 2)
        #expect(evidence["MARCUS"]!.sceneHeadings.contains("INT. OFFICE - DAY"))
        #expect(evidence["MARCUS"]!.sceneHeadings.contains("EXT. PARK - NIGHT"))
    }

    @Test("Action mentions are detected case-insensitively")
    func correctActionMentions() {
        let elements = makeMockElements()
        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // "Elena walks into the room and sits down." mentions ELENA
        #expect(evidence["ELENA"]!.actionMentions.count == 1)
        #expect(evidence["ELENA"]!.actionMentions[0].contains("Elena"))

        // "Marcus sits on a bench, staring at the sky." mentions MARCUS
        #expect(evidence["MARCUS"]!.actionMentions.count == 1)
        #expect(evidence["MARCUS"]!.actionMentions[0].contains("Marcus"))
    }

    @Test("Character name extensions like (V.O.) and (CONT'D) are stripped")
    func characterNameNormalization() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. STUDIO - DAY"),
            GuionElement(elementType: .character, elementText: "ELENA (V.O.)"),
            GuionElement(elementType: .dialogue, elementText: "This is a voiceover line."),
            GuionElement(elementType: .character, elementText: "ELENA (CONT'D)"),
            GuionElement(elementType: .dialogue, elementText: "And this continues."),
        ]

        let evidence = CharacterEvidenceExtractor.extract(from: elements)

        // Both should be normalized to "ELENA"
        #expect(evidence.count == 1)
        #expect(evidence["ELENA"] != nil)
        #expect(evidence["ELENA"]!.dialogueLines.count == 2)
    }

    @Test("Empty element array produces empty evidence")
    func emptyElements() {
        let evidence = CharacterEvidenceExtractor.extract(from: [])
        #expect(evidence.isEmpty)
    }

    @Test("Elements with no dialogue produce no evidence")
    func noDialogueElements() {
        let elements: [GuionElement] = [
            GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
            GuionElement(elementType: .action, elementText: "The room is empty."),
            GuionElement(elementType: .transition, elementText: "CUT TO:"),
        ]

        let evidence = CharacterEvidenceExtractor.extract(from: elements)
        #expect(evidence.isEmpty)
    }
}
