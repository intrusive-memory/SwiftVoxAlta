//
//  ParentheticalMapperTests.swift
//  SwiftVoxAltaTests
//
//  Tests parenthetical-to-TTS-instruct mapping including static lookups and normalization.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("ParentheticalMapper Tests")
struct ParentheticalMapperTests {

    // MARK: - Vocal Mappings

    @Test("Whispering maps to whisper instruct")
    func whispering() {
        let result = ParentheticalMapper.mapToInstruct("(whispering)")
        #expect(result == "speak in a whisper")
    }

    @Test("Shouting maps to loud instruct")
    func shouting() {
        let result = ParentheticalMapper.mapToInstruct("(shouting)")
        #expect(result == "speak loudly and forcefully")
    }

    @Test("Sarcastic maps to sarcastic instruct")
    func sarcastic() {
        let result = ParentheticalMapper.mapToInstruct("(sarcastic)")
        #expect(result == "speak with a sarcastic tone")
    }

    @Test("Angrily maps to angry instruct")
    func angrily() {
        let result = ParentheticalMapper.mapToInstruct("(angrily)")
        #expect(result == "speak angrily")
    }

    @Test("Softly maps to soft instruct")
    func softly() {
        let result = ParentheticalMapper.mapToInstruct("(softly)")
        #expect(result == "speak softly and gently")
    }

    @Test("Laughing maps to laughing instruct")
    func laughing() {
        let result = ParentheticalMapper.mapToInstruct("(laughing)")
        #expect(result == "speak while laughing")
    }

    @Test("Crying maps to crying instruct")
    func crying() {
        let result = ParentheticalMapper.mapToInstruct("(crying)")
        #expect(result == "speak while crying, with emotion")
    }

    @Test("Nervously maps to nervous instruct")
    func nervously() {
        let result = ParentheticalMapper.mapToInstruct("(nervously)")
        #expect(result == "speak nervously, with hesitation")
    }

    @Test("Excited maps to excited instruct")
    func excited() {
        let result = ParentheticalMapper.mapToInstruct("(excited)")
        #expect(result == "speak with excitement and energy")
    }

    @Test("Monotone maps to monotone instruct")
    func monotone() {
        let result = ParentheticalMapper.mapToInstruct("(monotone)")
        #expect(result == "speak in a flat, monotone voice")
    }

    @Test("Singing maps to sing-song instruct")
    func singing() {
        let result = ParentheticalMapper.mapToInstruct("(singing)")
        #expect(result == "speak in a sing-song manner")
    }

    @Test("'to herself' maps to talking-to-oneself instruct")
    func toHerself() {
        let result = ParentheticalMapper.mapToInstruct("(to herself)")
        #expect(result == "speak quietly, as if talking to oneself")
    }

    @Test("'to himself' maps to talking-to-oneself instruct")
    func toHimself() {
        let result = ParentheticalMapper.mapToInstruct("(to himself)")
        #expect(result == "speak quietly, as if talking to oneself")
    }

    // MARK: - Blocking Parentheticals (nil)

    @Test("'beat' returns nil (blocking)")
    func beat() {
        let result = ParentheticalMapper.mapToInstruct("(beat)")
        #expect(result == nil)
    }

    @Test("'pause' returns nil (blocking)")
    func pause() {
        let result = ParentheticalMapper.mapToInstruct("(pause)")
        #expect(result == nil)
    }

    @Test("'turning' returns nil (blocking)")
    func turning() {
        let result = ParentheticalMapper.mapToInstruct("(turning)")
        #expect(result == nil)
    }

    @Test("'walking away' returns nil (blocking)")
    func walkingAway() {
        let result = ParentheticalMapper.mapToInstruct("(walking away)")
        #expect(result == nil)
    }

    @Test("'standing' returns nil (blocking)")
    func standing() {
        let result = ParentheticalMapper.mapToInstruct("(standing)")
        #expect(result == nil)
    }

    @Test("'sitting' returns nil (blocking)")
    func sitting() {
        let result = ParentheticalMapper.mapToInstruct("(sitting)")
        #expect(result == nil)
    }

    // MARK: - Normalization

    @Test("Parenthetical without outer parens is still matched")
    func withoutParens() {
        let result = ParentheticalMapper.mapToInstruct("whispering")
        #expect(result == "speak in a whisper")
    }

    @Test("Mixed case parenthetical is normalized")
    func mixedCase() {
        let result = ParentheticalMapper.mapToInstruct("(WHISPERING)")
        #expect(result == "speak in a whisper")
    }

    @Test("Mixed case without parens is normalized")
    func mixedCaseNoParens() {
        let result = ParentheticalMapper.mapToInstruct("Sarcastic")
        #expect(result == "speak with a sarcastic tone")
    }

    @Test("Extra whitespace is trimmed during normalization")
    func extraWhitespace() {
        let result = ParentheticalMapper.mapToInstruct("(  whispering  )")
        #expect(result == "speak in a whisper")
    }

    @Test("Leading/trailing whitespace on outer string is trimmed")
    func outerWhitespace() {
        let result = ParentheticalMapper.mapToInstruct("  (shouting)  ")
        #expect(result == "speak loudly and forcefully")
    }

    @Test("Blocking parenthetical with mixed case returns nil")
    func blockingMixedCase() {
        let result = ParentheticalMapper.mapToInstruct("(BEAT)")
        #expect(result == nil)
    }

    // MARK: - Unknown Parentheticals

    @Test("Unknown parenthetical returns nil from static mapper")
    func unknownParenthetical() {
        let result = ParentheticalMapper.mapToInstruct("(dramatically)")
        #expect(result == nil)
    }

    @Test("Empty parenthetical returns nil")
    func emptyParenthetical() {
        let result = ParentheticalMapper.mapToInstruct("()")
        #expect(result == nil)
    }

    @Test("Empty string returns nil")
    func emptyString() {
        let result = ParentheticalMapper.mapToInstruct("")
        #expect(result == nil)
    }

    // MARK: - Normalize Function

    @Test("normalize strips parens and lowercases")
    func normalizeFunction() {
        let normalized = ParentheticalMapper.normalize("(WHISPERING)")
        #expect(normalized == "whispering")
    }

    @Test("normalize handles no parens")
    func normalizeNoParens() {
        let normalized = ParentheticalMapper.normalize("Shouting")
        #expect(normalized == "shouting")
    }

    @Test("normalize handles inner whitespace preservation")
    func normalizeInnerWhitespace() {
        let normalized = ParentheticalMapper.normalize("(to herself)")
        #expect(normalized == "to herself")
    }

    // MARK: - Synonym Coverage

    @Test("Sarcastically maps same as sarcastic")
    func sarcastically() {
        let result = ParentheticalMapper.mapToInstruct("(sarcastically)")
        #expect(result == "speak with a sarcastic tone")
    }

    @Test("Yelling maps same as shouting")
    func yelling() {
        let result = ParentheticalMapper.mapToInstruct("(yelling)")
        #expect(result == "speak loudly and forcefully")
    }

    @Test("Quietly maps same as softly")
    func quietly() {
        let result = ParentheticalMapper.mapToInstruct("(quietly)")
        #expect(result == "speak softly and gently")
    }
}
