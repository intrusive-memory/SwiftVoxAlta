import Foundation
import NaturalLanguage

/// Splits text into chunks suitable for sequential TTS synthesis.
///
/// Uses `NLTokenizer` with `.sentence` unit to split text on sentence boundaries,
/// then groups sentences into chunks of approximately `maxWordsPerChunk` words.
/// Sentences are never split mid-sentence; a single sentence longer than the
/// maximum word count is emitted as its own chunk.
enum TextChunker: Sendable {

    /// The default maximum number of words per chunk.
    /// Qwen3-TTS handles ~200 words per generation well.
    static let defaultMaxWordsPerChunk = 200

    /// Split text into chunks of approximately `maxWords` words,
    /// breaking only on sentence boundaries.
    ///
    /// - Parameters:
    ///   - text: The input text to chunk.
    ///   - maxWords: Maximum words per chunk. Defaults to ``defaultMaxWordsPerChunk``.
    /// - Returns: An array of text chunks. Returns an empty array for empty/whitespace-only input.
    static func chunk(_ text: String, maxWords: Int = defaultMaxWordsPerChunk) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let sentences = splitSentences(trimmed)

        // If NLTokenizer found no sentences (unlikely but defensive), return the whole text.
        guard !sentences.isEmpty else {
            return [trimmed]
        }

        return groupSentences(sentences, maxWords: maxWords)
    }

    // MARK: - Private

    /// Split text into sentences using NLTokenizer.
    ///
    /// - Parameter text: The input text.
    /// - Returns: An array of sentence strings, preserving original whitespace within each sentence.
    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        // Fallback: if NLTokenizer produces nothing, treat the whole text as one sentence.
        if sentences.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return sentences
    }

    /// Group sentences into chunks that do not exceed `maxWords` words.
    ///
    /// A single sentence that exceeds `maxWords` on its own is placed in its
    /// own chunk without further splitting — we never break mid-sentence.
    ///
    /// - Parameters:
    ///   - sentences: An array of sentence strings.
    ///   - maxWords: The maximum word count target per chunk.
    /// - Returns: An array of chunk strings, each containing one or more sentences.
    private static func groupSentences(_ sentences: [String], maxWords: Int) -> [String] {
        var chunks: [String] = []
        var currentSentences: [String] = []
        var currentWordCount = 0

        for sentence in sentences {
            let sentenceWordCount = wordCount(sentence)

            // If adding this sentence would exceed the limit and we already have content,
            // finalize the current chunk first.
            if currentWordCount + sentenceWordCount > maxWords && !currentSentences.isEmpty {
                chunks.append(currentSentences.joined(separator: " "))
                currentSentences = []
                currentWordCount = 0
            }

            currentSentences.append(sentence)
            currentWordCount += sentenceWordCount
        }

        // Flush remaining sentences.
        if !currentSentences.isEmpty {
            chunks.append(currentSentences.joined(separator: " "))
        }

        return chunks
    }

    /// Count words in a string using whitespace splitting.
    ///
    /// - Parameter text: The text to count words in.
    /// - Returns: The number of whitespace-separated tokens.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
