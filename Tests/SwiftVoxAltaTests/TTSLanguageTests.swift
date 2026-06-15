//
//  TTSLanguageTests.swift
//  SwiftVoxAltaTests
//
//  Verifies language-tag resolution into the model-aligned TTSLanguage enum,
//  including the lossy region drop and the throwing behavior on unsupported tags.
//

import Foundation
import Testing

@testable import SwiftVoxAlta

@Suite("TTSLanguage Resolution")
struct TTSLanguageTests {

  @Test("ISO 639-1 codes resolve to the matching case")
  func iso639Resolves() throws {
    #expect(try TTSLanguage(languageCode: "en") == .english)
    #expect(try TTSLanguage(languageCode: "zh") == .chinese)
    #expect(try TTSLanguage(languageCode: "es") == .spanish)
    #expect(try TTSLanguage(languageCode: "ja") == .japanese)
  }

  @Test("Resolution is case-insensitive and trims whitespace")
  func caseAndWhitespace() throws {
    #expect(try TTSLanguage(languageCode: "EN") == .english)
    #expect(try TTSLanguage(languageCode: "  fr  ") == .french)
  }

  @Test("Regional English tags collapse to generic english (region is dropped)")
  func regionalEnglishCollapses() throws {
    #expect(try TTSLanguage(languageCode: "en-GB") == .english)
    #expect(try TTSLanguage(languageCode: "en_US") == .english)
    #expect(try TTSLanguage(languageCode: "en-AU") == .english)
  }

  @Test("Full language names and model-name forms resolve")
  func namesAndAliases() throws {
    #expect(try TTSLanguage(languageCode: "english") == .english)
    #expect(try TTSLanguage(languageCode: "beijing_dialect") == .beijingDialect)
    #expect(try TTSLanguage(languageCode: "sichuan") == .sichuanDialect)
  }

  @Test("auto is an explicit, valid pass-through")
  func autoPassThrough() throws {
    #expect(try TTSLanguage(languageCode: "auto") == .auto)
  }

  @Test("modelName matches the on-device codec_language_id keys")
  func modelNames() {
    #expect(TTSLanguage.english.modelName == "english")
    #expect(TTSLanguage.beijingDialect.modelName == "beijing_dialect")
    #expect(TTSLanguage.sichuanDialect.modelName == "sichuan_dialect")
    #expect(TTSLanguage.auto.modelName == "auto")
  }

  @Test("Locale init resolves the language component")
  func localeInit() throws {
    #expect(try TTSLanguage(locale: Locale(identifier: "en_GB")) == .english)
    #expect(try TTSLanguage(locale: Locale(identifier: "de_DE")) == .german)
  }

  @Test("Unsupported languages throw unsupportedLanguage")
  func unsupportedThrows() {
    #expect(throws: VoxAltaError.self) {
      _ = try TTSLanguage(languageCode: "xx")
    }
    // Dutch is a real language but not in the model's 12 supported languages.
    #expect(throws: VoxAltaError.self) {
      _ = try TTSLanguage(languageCode: "nl")
    }
  }

  @Test("Every case has a non-empty modelName")
  func allCasesHaveModelName() {
    for lang in TTSLanguage.allCases {
      #expect(!lang.modelName.isEmpty)
    }
  }
}
