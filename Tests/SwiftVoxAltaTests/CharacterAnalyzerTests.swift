//
//  CharacterAnalyzerTests.swift
//  SwiftVoxAltaTests
//
//  Tests for CharacterAnalyzer prompt formatting and API shape.
//  Note: Tests requiring actual LLM model inference are skipped since
//  they depend on a downloaded model being available on the machine.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("CharacterAnalyzer Tests")
struct CharacterAnalyzerTests {

    // MARK: - Helper

    /// Creates a rich CharacterEvidence instance for testing prompt formatting.
    private func makeRichEvidence() -> CharacterEvidence {
        CharacterEvidence(
            characterName: "ELENA",
            dialogueLines: [
                "We need to talk about the plan.",
                "They're watching us.",
                "I'm always right.",
            ],
            parentheticals: [
                "(whispering)",
                "(firmly)",
            ],
            sceneHeadings: [
                "INT. OFFICE - DAY",
                "EXT. PARK - NIGHT",
            ],
            actionMentions: [
                "Elena walks into the room and sits down.",
                "Elena glances nervously at the door.",
            ]
        )
    }

    /// Creates a minimal CharacterEvidence with only a name and one dialogue line.
    private func makeMinimalEvidence() -> CharacterEvidence {
        CharacterEvidence(
            characterName: "GHOST",
            dialogueLines: ["Boo."]
        )
    }

    // MARK: - Prompt Formatting Tests

    @Test("User prompt includes character name")
    func promptIncludesCharacterName() {
        let evidence = makeRichEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("CHARACTER NAME: ELENA"))
    }

    @Test("User prompt includes all dialogue lines")
    func promptIncludesDialogue() {
        let evidence = makeRichEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("DIALOGUE LINES:"))
        #expect(prompt.contains("We need to talk about the plan."))
        #expect(prompt.contains("They're watching us."))
        #expect(prompt.contains("I'm always right."))
    }

    @Test("User prompt includes parentheticals")
    func promptIncludesParentheticals() {
        let evidence = makeRichEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("PARENTHETICAL DIRECTIONS:"))
        #expect(prompt.contains("(whispering)"))
        #expect(prompt.contains("(firmly)"))
    }

    @Test("User prompt includes scene headings")
    func promptIncludesSceneHeadings() {
        let evidence = makeRichEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("SCENES WHERE CHARACTER APPEARS:"))
        #expect(prompt.contains("INT. OFFICE - DAY"))
        #expect(prompt.contains("EXT. PARK - NIGHT"))
    }

    @Test("User prompt includes action mentions")
    func promptIncludesActionMentions() {
        let evidence = makeRichEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("ACTION DESCRIPTIONS MENTIONING CHARACTER:"))
        #expect(prompt.contains("Elena walks into the room and sits down."))
        #expect(prompt.contains("Elena glances nervously at the door."))
    }

    @Test("User prompt omits empty sections")
    func promptOmitsEmptySections() {
        let evidence = makeMinimalEvidence()
        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("CHARACTER NAME: GHOST"))
        #expect(prompt.contains("DIALOGUE LINES:"))
        #expect(prompt.contains("Boo."))

        // These sections should not appear for minimal evidence
        #expect(!prompt.contains("PARENTHETICAL DIRECTIONS:"))
        #expect(!prompt.contains("SCENES WHERE CHARACTER APPEARS:"))
        #expect(!prompt.contains("ACTION DESCRIPTIONS MENTIONING CHARACTER:"))
    }

    @Test("User prompt truncates excess dialogue lines with count")
    func promptTruncatesExcessDialogue() {
        // Create evidence with 25 dialogue lines
        let lines = (1...25).map { "Line number \($0)." }
        let evidence = CharacterEvidence(
            characterName: "VERBOSE",
            dialogueLines: lines
        )

        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        // Should include first 20 lines
        #expect(prompt.contains("Line number 1."))
        #expect(prompt.contains("Line number 20."))
        // Should NOT include line 21+
        #expect(!prompt.contains("Line number 21."))
        // Should show truncation note
        #expect(prompt.contains("... and 5 more lines"))
    }

    @Test("User prompt truncates excess action mentions with count")
    func promptTruncatesExcessActionMentions() {
        let mentions = (1...15).map { "Action mention \($0)." }
        let evidence = CharacterEvidence(
            characterName: "BUSY",
            actionMentions: mentions
        )

        let prompt = CharacterAnalyzer.formatUserPrompt(from: evidence)

        #expect(prompt.contains("Action mention 1."))
        #expect(prompt.contains("Action mention 10."))
        #expect(!prompt.contains("Action mention 11."))
        #expect(prompt.contains("... and 5 more mentions"))
    }

    // MARK: - System Prompt Tests

    @Test("System prompt mentions JSON output format")
    func systemPromptMentionsJSON() {
        let system = CharacterAnalyzer.systemPrompt

        #expect(system.contains("JSON"))
        #expect(system.contains("name"))
        #expect(system.contains("gender"))
        #expect(system.contains("ageRange"))
        #expect(system.contains("description"))
        #expect(system.contains("voiceTraits"))
        #expect(system.contains("summary"))
    }

    @Test("System prompt specifies valid gender values")
    func systemPromptSpecifiesGenderValues() {
        let system = CharacterAnalyzer.systemPrompt

        #expect(system.contains("male"))
        #expect(system.contains("female"))
        #expect(system.contains("nonBinary"))
        #expect(system.contains("unknown"))
    }

    // MARK: - API Shape (Compile Tests)

    @Test("analyze method exists with correct signature")
    func analyzeMethodExists() {
        // This test verifies the method signature compiles correctly.
        // We cannot call it without a real LLM model, so we just verify
        // the function reference type is correct.
        let _: (CharacterEvidence, String) async throws -> CharacterProfile =
            CharacterAnalyzer.analyze(evidence:model:)

        // If this compiles, the API shape is correct.
    }

    // MARK: - LLM Integration Tests (Skipped — require model download)

    // NOTE: The following tests require a downloaded LLM model on the machine
    // and would take significant time to run. They are commented out but
    // documented here for manual integration testing.
    //
    // @Test("analyze produces valid CharacterProfile from rich evidence")
    // func analyzeRichEvidence() async throws {
    //     let evidence = makeRichEvidence()
    //     let profile = try await CharacterAnalyzer.analyze(evidence: evidence)
    //     #expect(profile.name == "ELENA")
    //     #expect(!profile.summary.isEmpty)
    //     #expect(!profile.voiceTraits.isEmpty)
    // }
    //
    // @Test("analyze wraps LLM errors in profileAnalysisFailed")
    // func analyzeWithBadModel() async {
    //     let evidence = makeMinimalEvidence()
    //     do {
    //         _ = try await CharacterAnalyzer.analyze(
    //             evidence: evidence,
    //             model: "nonexistent/model-that-does-not-exist"
    //         )
    //         Issue.record("Expected profileAnalysisFailed error")
    //     } catch let error as VoxAltaError {
    //         guard case .profileAnalysisFailed = error else {
    //             Issue.record("Expected profileAnalysisFailed, got \(error)")
    //             return
    //         }
    //     } catch {
    //         Issue.record("Unexpected error type: \(error)")
    //     }
    // }
}
