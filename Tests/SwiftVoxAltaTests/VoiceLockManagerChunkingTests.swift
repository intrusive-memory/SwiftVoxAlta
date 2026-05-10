//
//  VoiceLockManagerChunkingTests.swift
//  SwiftVoxAltaTests
//
//  Unit tests for the sentence-chunking helpers in VoiceLockManager.
//  Covers the pure-string and silence-array surface area; the chunked
//  generation path itself requires a loaded model and is exercised by
//  integration tests.
//

import Foundation
@preconcurrency import MLX
import Testing

@testable import SwiftVoxAlta

@Suite("VoiceLockManager - Sentence Chunking", .acervoEnvironment)
struct VoiceLockManagerChunkingTests {

  // MARK: - estimateDuration

  @Test("estimateDuration is linear in character count")
  func estimateDurationLinear() {
    let short = VoiceLockManager.estimateDuration(text: String(repeating: "a", count: 100))
    let long = VoiceLockManager.estimateDuration(text: String(repeating: "a", count: 200))
    #expect(abs(long - 2.0 * short) < 0.001)
  }

  @Test("estimateDuration uses calibrated 0.055 s/char rate")
  func estimateDurationCalibration() {
    // Calibration source: chapter 2 element 11 (421 chars → 23.12s).
    let text = String(repeating: "x", count: 421)
    let estimated = VoiceLockManager.estimateDuration(text: text)
    #expect(abs(estimated - 23.155) < 0.1)
  }

  @Test("estimateDuration returns zero for empty input")
  func estimateDurationEmpty() {
    #expect(VoiceLockManager.estimateDuration(text: "") == 0.0)
  }

  // MARK: - splitAtSentences: passthrough cases

  @Test("Short single sentence passes through as one chunk")
  func splitShortSingleSentence() {
    let text = "Hello, this is a single sentence."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks == [text])
  }

  @Test("Empty input yields empty array")
  func splitEmptyInput() {
    #expect(VoiceLockManager.splitAtSentences(text: "", maxDuration: 10.0) == [])
  }

  @Test("Whitespace-only input yields empty array")
  func splitWhitespaceOnly() {
    #expect(VoiceLockManager.splitAtSentences(text: "   \n\t  ", maxDuration: 10.0) == [])
  }

  @Test("Sentence with no terminal punctuation is preserved as single chunk")
  func splitNoTerminalPunctuation() {
    let text = "this has no terminal punctuation"
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count == 1)
    #expect(chunks.first == text)
  }

  // MARK: - splitAtSentences: packing

  @Test("Multiple short sentences pack into one chunk when combined fits under maxDuration")
  func splitPacksShortSentencesTogether() {
    let text = "First. Second. Third."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count == 1)
  }

  @Test("Long prose splits into multiple chunks at sentence boundaries")
  func splitLongProseIntoMultipleChunks() {
    // ~600 chars at 0.055 s/char → ~33s. With maxDuration 10s, expect ~3 chunks.
    let sentence =
      "The quick brown fox jumps over the lazy dog while the rain falls on the rooftops of the village. "
    let text = String(repeating: sentence, count: 6)
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count >= 2)
    for chunk in chunks {
      // Chunks normally stay under maxDuration, but the runt-merge rule
      // (currentChunk.count < minimumChunkSize) intentionally overruns to avoid
      // emitting a sub-minimumChunkSize chunk. Allow either condition.
      let underDurationCap = VoiceLockManager.estimateDuration(text: chunk) <= 10.0 + 0.001
      let runtMerged = chunk.count >= VoiceLockManager.minimumChunkSize
      #expect(underDurationCap || runtMerged || chunk == text)
    }
  }

  @Test("Single sentence longer than maxDuration is emitted as its own oversized chunk")
  func splitOversizedSingleSentenceEmittedWhole() {
    // ~400 chars (~22s) with NO sentence boundary inside.
    let text = String(repeating: "abcdefghij ", count: 40).trimmingCharacters(in: .whitespaces)
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 5.0)
    #expect(chunks.count == 1)
    #expect(chunks.first == text)
  }

  @Test("Concatenated chunks contain all original sentence content")
  func splitPreservesContent() {
    let text =
      "First sentence here. Second sentence here. Third sentence here. Fourth sentence here. Fifth sentence here. Sixth sentence here. Seventh sentence here."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 3.0)
    let recombined = chunks.joined(separator: " ")
    for marker in [
      "First sentence here", "Second sentence here", "Third sentence here", "Fourth sentence here",
      "Fifth sentence here", "Sixth sentence here", "Seventh sentence here",
    ] {
      #expect(recombined.contains(marker))
    }
  }

  // MARK: - splitAtSentences: ICU correctness (the regex-killer cases)

  @Test("Abbreviations like 'Dr.' and 'Mr.' do not trigger false sentence breaks")
  func splitHandlesAbbreviations() {
    let text = "Dr. Smith met Mr. Jones at the office. They discussed the project."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    // ICU should produce 2 sentences. A naive regex on `.` would produce 4+.
    // Both fit in one chunk under maxDuration=10.0.
    #expect(chunks.count == 1)
    #expect(chunks.first?.contains("Dr. Smith") == true)
    #expect(chunks.first?.contains("Mr. Jones") == true)
  }

  @Test("Decimal numbers like '3.14' do not trigger false sentence breaks")
  func splitHandlesDecimals() {
    let text = "The value of pi is approximately 3.14 in most calculations. We use it for area."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count == 1)
    #expect(chunks.first?.contains("3.14") == true)
  }

  @Test("Version-like tokens 'v2.0' do not trigger false sentence breaks")
  func splitHandlesVersionTokens() {
    let text = "We released v2.0 last week and v2.1 this morning. The team is celebrating."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count == 1)
    #expect(chunks.first?.contains("v2.0") == true)
    #expect(chunks.first?.contains("v2.1") == true)
  }

  @Test("Ellipses do not trigger spurious chunk breaks at small maxDuration")
  func splitHandlesEllipses() {
    // Two real sentences separated by terminal punctuation, each with internal ellipses.
    let text = "She paused... thinking carefully. Then she spoke with conviction."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    #expect(chunks.count == 1)
  }

  @Test("Em-dash content stays intact within a sentence")
  func splitPreservesEmDashes() {
    // Em-dash is intentionally NOT used as a chunk boundary (per design decision).
    let text = "Beauty exists—ugliness defines it. Good exists—evil shapes it."
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 10.0)
    let joined = chunks.joined(separator: " ")
    #expect(joined.contains("Beauty exists—ugliness defines it"))
    #expect(joined.contains("Good exists—evil shapes it"))
  }

  // MARK: - splitAtSentences: minimum chunk size enforcement

  @Test("Runt first sentence merges forward to meet minimum chunk size")
  func splitMergesRuntFirstSentence() {
    // 70-char first sentence (like the FIXME.md repro case) should merge forward
    // even if the second sentence would normally start a new chunk.
    let runtSentence = "The sage, understanding this principle, acts without forcing outcomes."
    let longSentence = String(
      repeating: "Additional context sentence with sufficient length for duration limits. ",
      count: 2)
    let text = runtSentence + " " + longSentence

    // Set maxDuration low enough that the combined text would normally split
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 5.0)

    // With minimum chunk size enforcement, the runt (70 chars) should merge forward
    // into the longer content rather than being emitted alone.
    #expect(chunks.count >= 1)
    if chunks.count == 1 {
      // Merged into one chunk (ideal)
      #expect(chunks[0].contains(runtSentence))
      #expect(chunks[0].count >= VoiceLockManager.minimumChunkSize)
    } else {
      // If split, verify the first chunk is not the runt alone
      #expect(!chunks[0].hasSuffix("forcing outcomes."))
      // Each chunk should meet minimum size
      for chunk in chunks {
        #expect(chunk.count >= VoiceLockManager.minimumChunkSize)
      }
    }
  }

  @Test("Chunks meeting minimum size are emitted normally")
  func splitEmitsNormalChunksAtMinimumSize() {
    // Two sentences, each >= 100 chars
    let sentence1 = String(repeating: "This is a sentence with sufficient length. ", count: 3)  // ~129 chars
    let sentence2 = String(repeating: "Another sentence with sufficient length too. ", count: 3)  // ~135 chars
    let text = sentence1 + sentence2

    // maxDuration that would split them (each is ~7s at 0.055 s/char)
    let chunks = VoiceLockManager.splitAtSentences(text: text, maxDuration: 8.0)

    // Both sentences are >= 100 chars, so should split normally
    #expect(chunks.count == 2)
    #expect(chunks[0].count >= VoiceLockManager.minimumChunkSize)
    #expect(chunks[1].count >= VoiceLockManager.minimumChunkSize)
  }

  // MARK: - generateSilenceArray

  @Test("Silence array length matches duration × sampleRate")
  func silenceArrayLengthMatchesDuration() {
    let array = VoiceLockManager.generateSilenceArray(duration: 0.25, sampleRate: 24000)
    #expect(array.shape == [6000])
  }

  @Test("Silence array is all zeros")
  func silenceArrayIsZeros() {
    let array = VoiceLockManager.generateSilenceArray(duration: 0.1, sampleRate: 24000)
    let samples: [Float] = array.asArray(Float.self)
    #expect(samples.allSatisfy { $0 == 0.0 })
  }

  @Test("Silence array of zero duration is empty (not negative-sized)")
  func silenceArrayZeroDuration() {
    let array = VoiceLockManager.generateSilenceArray(duration: 0.0, sampleRate: 24000)
    #expect(array.shape == [0])
  }

  @Test("Silence array of negative duration clamps to empty")
  func silenceArrayNegativeDurationClamps() {
    let array = VoiceLockManager.generateSilenceArray(duration: -1.0, sampleRate: 24000)
    #expect(array.shape == [0])
  }

  // MARK: - GenerationSettings defaults

  @Test("Default GenerationSettings has chunking enabled with 12s/0.25s defaults")
  func defaultSettingsChunkingEnabled() {
    let settings = GenerationSettings.default
    #expect(settings.enableAutoChunking == true)
    #expect(settings.chunkTargetDuration == 12.0)
    #expect(settings.chunkPauseDuration == 0.25)
  }

  // MARK: - chunkTargetDuration as the single handle

  @Test("Custom chunkTargetDuration round-trips through GenerationSettings init")
  func customChunkTargetDurationRoundTrip() {
    let custom = GenerationSettings(chunkTargetDuration: 7.5)
    #expect(custom.chunkTargetDuration == 7.5)
    // Other fields keep their defaults so callers can override one knob in isolation.
    #expect(custom.enableAutoChunking == GenerationSettings.default.enableAutoChunking)
    #expect(custom.chunkPauseDuration == GenerationSettings.default.chunkPauseDuration)
    #expect(custom.temperature == GenerationSettings.default.temperature)
  }

  /// Six independent ~6-second sentences (~36s of estimated audio total) with
  /// real word boundaries so ICU's `.bySentences` enumerator actually segments.
  /// Each sentence is ~109 chars ≈ 6.0s at the 0.055 s/char rate.
  private static let sixSentenceParagraph: String = """
    The quick brown fox jumped over the lazy dog while the sun set behind the distant mountain ridge here today. \
    Meanwhile a curious cat sat by the warm windowsill watching the autumn leaves swirl across the cobblestone path. \
    A gentle ocean breeze carried the salty scent of seaweed across the empty boardwalk in the late afternoon hours. \
    The old fisherman mended his weathered net beside the dock as gulls cried overhead in the gray morning light. \
    Children laughed and chased each other through the sprinkler in the front yard while the radio played softly inside. \
    Her grandmother kneaded the dough with practiced hands while the kettle whistled on the stove in the back kitchen.
    """

  @Test("chunkTargetDuration drives chunk granularity end-to-end")
  func chunkTargetDurationControlsGranularity() {
    let text = Self.sixSentenceParagraph

    // Tight setting: every sentence becomes its own chunk.
    let tight = GenerationSettings(chunkTargetDuration: 6.0)
    let tightChunks = VoiceLockManager.splitAtSentences(
      text: text,
      maxDuration: tight.chunkTargetDuration
    )

    // Loose setting: whole paragraph fits in a single chunk.
    let loose = GenerationSettings(chunkTargetDuration: 60.0)
    let looseChunks = VoiceLockManager.splitAtSentences(
      text: text,
      maxDuration: loose.chunkTargetDuration
    )

    #expect(
      tightChunks.count > looseChunks.count,
      "Tight chunkTargetDuration should produce more chunks: tight=\(tightChunks.count) vs loose=\(looseChunks.count)"
    )
    #expect(looseChunks.count == 1)
  }

  @Test("Default chunkTargetDuration leaves short input as a single chunk")
  func defaultLeavesShortInputUnchunked() {
    // ~3.6s of audio (well under the 12s default).
    let short = "Hello there friend. This is short. Just three sentences here."
    let chunks = VoiceLockManager.splitAtSentences(
      text: short,
      maxDuration: GenerationSettings.default.chunkTargetDuration
    )
    #expect(chunks.count == 1)
  }

}
