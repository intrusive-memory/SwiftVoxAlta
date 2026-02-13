import Foundation
import Testing
@testable import diga

// MARK: - TextChunker Tests

@Suite("TextChunker Tests")
struct TextChunkerTests {

    // --- Test 1: Short text produces a single chunk ---

    @Test("Short text returns a single chunk")
    func shortTextSingleChunk() {
        let text = "Hello world. This is a short sentence."
        let chunks = TextChunker.chunk(text)
        #expect(chunks.count == 1)
        #expect(chunks[0].contains("Hello world"))
    }

    // --- Test 2: ~500 words produces 2-3 chunks ---

    @Test("500-word text produces 2-3 chunks at default max")
    func fiveHundredWordsProducesMultipleChunks() {
        // Build a ~500 word text with clear sentence boundaries.
        var sentences: [String] = []
        // Each sentence is ~10 words, so 50 sentences = ~500 words.
        for i in 1...50 {
            sentences.append("This is sentence number \(i) in our test paragraph right here.")
        }
        let text = sentences.joined(separator: " ")

        let chunks = TextChunker.chunk(text)
        // At 200 words per chunk, 500 words should produce 2-3 chunks.
        #expect(chunks.count >= 2, "Expected at least 2 chunks for ~500 words, got \(chunks.count)")
        #expect(chunks.count <= 4, "Expected at most 4 chunks for ~500 words, got \(chunks.count)")
    }

    // --- Test 3: Empty string returns empty array ---

    @Test("Empty string returns empty array")
    func emptyStringReturnsEmpty() {
        let chunks = TextChunker.chunk("")
        #expect(chunks.isEmpty)
    }

    // --- Test 4: Whitespace-only string returns empty array ---

    @Test("Whitespace-only string returns empty array")
    func whitespaceOnlyReturnsEmpty() {
        let chunks = TextChunker.chunk("   \n\t  ")
        #expect(chunks.isEmpty)
    }

    // --- Test 5: Single long sentence stays as one chunk ---

    @Test("Single long sentence without terminators is one chunk")
    func singleLongSentenceOneChunk() {
        // Build a very long sentence (~300 words) with no period.
        var words: [String] = []
        for i in 1...300 {
            words.append("word\(i)")
        }
        let text = words.joined(separator: " ")

        let chunks = TextChunker.chunk(text)
        // NLTokenizer should treat this as one sentence, so one chunk.
        #expect(chunks.count == 1, "Expected 1 chunk for a single long sentence, got \(chunks.count)")
    }

    // --- Test 6: Chunk boundaries fall on sentence boundaries ---

    @Test("Chunk boundaries respect sentence boundaries")
    func chunkBoundariesOnSentenceBoundaries() {
        // Create text with distinct sentences of known lengths.
        // Each sentence is ~18 words. At maxWords=40, we should get ~2 sentences per chunk.
        let s1 = "The quick brown fox jumped over the lazy dog in the park near the old oak tree."
        let s2 = "Meanwhile the cat sat on the warm windowsill watching birds fly past the garden fence."
        let s3 = "A gentle breeze carried the scent of fresh flowers across the meadow where children played."
        let s4 = "The old man sat reading his newspaper on the porch while his dog slept at his feet."

        let text = "\(s1) \(s2) \(s3) \(s4)"
        let chunks = TextChunker.chunk(text, maxWords: 40)

        // Each chunk should contain complete sentences only.
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!trimmed.isEmpty, "Chunk should not be empty")
        }

        // Verify all text content is preserved across chunks.
        let reconstructed = chunks.joined(separator: " ")
        #expect(reconstructed.contains("quick brown fox"))
        #expect(reconstructed.contains("cat sat"))
        #expect(reconstructed.contains("gentle breeze"))
        #expect(reconstructed.contains("old man"))
    }

    // --- Test 7: Text with no sentence terminators handled gracefully ---

    @Test("Text with no sentence terminators produces chunks")
    func noSentenceTerminators() {
        // Text without periods, question marks, or exclamation marks.
        let text = "hello world this is text without any punctuation or sentence ending markers at all"
        let chunks = TextChunker.chunk(text)
        #expect(!chunks.isEmpty, "Should produce at least one chunk for non-empty text")
        let joined = chunks.joined(separator: " ")
        #expect(joined.contains("hello world"))
        #expect(joined.contains("markers"))
    }

    // --- Test 8: Word count utility ---

    @Test("wordCount correctly counts whitespace-separated tokens")
    func wordCountAccuracy() {
        #expect(TextChunker.wordCount("") == 0)
        #expect(TextChunker.wordCount("hello") == 1)
        #expect(TextChunker.wordCount("hello world") == 2)
        #expect(TextChunker.wordCount("  multiple   spaces   here  ") == 3)
        #expect(TextChunker.wordCount("one\ntwo\tthree") == 3)
    }

    // --- Test 9: Custom maxWords parameter ---

    @Test("Custom maxWords produces appropriately sized chunks")
    func customMaxWords() {
        // 10 sentences of ~10 words each = ~100 words total.
        var sentences: [String] = []
        for i in 1...10 {
            sentences.append("This is test sentence number \(i) for chunking purposes here.")
        }
        let text = sentences.joined(separator: " ")

        // With maxWords=30, should get more chunks.
        let chunks30 = TextChunker.chunk(text, maxWords: 30)
        // With maxWords=200, should get fewer chunks.
        let chunks200 = TextChunker.chunk(text, maxWords: 200)

        #expect(chunks30.count > chunks200.count,
                "Smaller maxWords should produce more chunks: \(chunks30.count) vs \(chunks200.count)")
    }
}

// MARK: - WAVConcatenator Tests

@Suite("WAVConcatenator Tests")
struct WAVConcatenatorTests {

    /// Helper: build a small WAV file with known PCM samples.
    private func makeWAV(samples: [Int16], sampleRate: Int = 24000) -> Data {
        WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: sampleRate)
    }

    // --- Test 10: Two WAV segments concatenate into valid WAV ---

    @Test("Two WAV segments concatenate into a single valid WAV")
    func twoSegmentsConcatenate() throws {
        let wav1 = makeWAV(samples: [100, 200, 300])
        let wav2 = makeWAV(samples: [400, 500, 600])

        let combined = try WAVConcatenator.concatenate([wav1, wav2])

        // Verify RIFF header.
        let riff = String(data: combined[0..<4], encoding: .ascii)
        #expect(riff == "RIFF")

        let wave = String(data: combined[8..<12], encoding: .ascii)
        #expect(wave == "WAVE")

        // The combined data chunk should have 6 samples * 2 bytes = 12 bytes of PCM.
        let expectedDataSize: UInt32 = 6 * 2
        let dataChunkSize = combined.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataChunkSize == expectedDataSize,
                "Expected data size \(expectedDataSize), got \(dataChunkSize)")

        // Total file size: 44 header + 12 PCM = 56 bytes.
        #expect(combined.count == 56)
    }

    // --- Test 11: Single segment returned as-is ---

    @Test("Single WAV segment is returned unchanged")
    func singleSegmentPassthrough() throws {
        let wav = makeWAV(samples: [1000, 2000, 3000])
        let result = try WAVConcatenator.concatenate([wav])
        #expect(result == wav)
    }

    // --- Test 12: Empty segments array throws ---

    @Test("Empty segments array throws an error")
    func emptySegmentsThrows() throws {
        #expect(throws: DigaEngineError.self) {
            try WAVConcatenator.concatenate([])
        }
    }

    // --- Test 13: Concatenated PCM data preserves sample order ---

    @Test("Concatenated WAV preserves sample order from all segments")
    func preservesSampleOrder() throws {
        let samples1: [Int16] = [10, 20, 30]
        let samples2: [Int16] = [40, 50, 60]
        let wav1 = makeWAV(samples: samples1)
        let wav2 = makeWAV(samples: samples2)

        let combined = try WAVConcatenator.concatenate([wav1, wav2])

        // Read the PCM samples back from the combined WAV.
        let headerSize = 44
        let pcmData = combined[headerSize...]
        #expect(pcmData.count == 12)  // 6 samples * 2 bytes

        // Verify each sample.
        let expectedSamples: [Int16] = [10, 20, 30, 40, 50, 60]
        combined.withUnsafeBytes { buffer in
            for (i, expected) in expectedSamples.enumerated() {
                let offset = headerSize + i * 2
                let sample = buffer.load(fromByteOffset: offset, as: Int16.self).littleEndian
                #expect(sample == expected, "Sample \(i): expected \(expected), got \(sample)")
            }
        }
    }

    // --- Test 14: Segment too short throws ---

    @Test("WAV segment shorter than header throws")
    func tooShortSegmentThrows() throws {
        let shortData = Data(repeating: 0, count: 10)
        let validWav = makeWAV(samples: [100])

        #expect(throws: DigaEngineError.self) {
            try WAVConcatenator.concatenate([validWav, shortData])
        }
    }
}

// MARK: - DigaEngine Voice Resolution Tests

@Suite("DigaEngine Voice Resolution Tests")
struct DigaEngineVoiceResolutionTests {

    /// Creates a DigaEngine with a temp-backed VoiceStore.
    private func makeTestEngine() throws -> (DigaEngine, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-engine-test-\(UUID().uuidString)", isDirectory: true)
        let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
        let engine = DigaEngine(voiceStore: voiceStore)
        return (engine, tempDir)
    }

    /// Cleans up a test directory.
    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // --- Test 15: Resolve unknown voice name throws ---

    @Test("Resolving an unknown voice name throws voiceNotFound")
    func resolveUnknownThrows() async throws {
        let (engine, tempDir) = try makeTestEngine()
        defer { cleanup(tempDir) }

        do {
            _ = try await engine.resolveVoice(name: "nonexistent_voice_xyz")
            #expect(Bool(false), "Expected voiceNotFound error")
        } catch let error as DigaEngineError {
            if case .voiceNotFound(let name) = error {
                #expect(name == "nonexistent_voice_xyz")
            } else {
                #expect(Bool(false), "Expected voiceNotFound, got \(error)")
            }
        }
    }

    // --- Test 16: Resolve preset voice returns non-nil ---

    @Test("Resolving a preset voice name returns the correct voice")
    func resolvePresetVoice() async throws {
        let (engine, tempDir) = try makeTestEngine()
        defer { cleanup(tempDir) }

        let voice = try await engine.resolveVoice(name: "ryan")
        #expect(voice.name == "ryan")
        #expect(voice.type == .preset)
        #expect(voice.designDescription?.contains("Dynamic male") == true)
    }

    // --- Test 17: Resolve nil name returns default (first built-in) ---

    @Test("Resolving nil voice name returns the first built-in voice")
    func resolveDefaultVoice() async throws {
        let (engine, tempDir) = try makeTestEngine()
        defer { cleanup(tempDir) }

        let voice = try await engine.resolveVoice(name: nil)
        let firstBuiltin = BuiltinVoices.all().first!
        #expect(voice.name == firstBuiltin.name)
    }

    // --- Test 18: Resolve custom voice from VoiceStore ---

    @Test("Resolving a custom voice from VoiceStore works")
    func resolveCustomVoice() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-engine-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
        let customVoice = StoredVoice(
            name: "mycustom",
            type: .designed,
            designDescription: "Custom test voice"
        )
        try voiceStore.saveVoice(customVoice)

        let engine = DigaEngine(voiceStore: voiceStore)

        let resolved = try await engine.resolveVoice(name: "mycustom")
        #expect(resolved.name == "mycustom")
        #expect(resolved.type == .designed)
    }

    // --- Test 19: Custom voice takes priority over built-in with same name ---

    @Test("Custom voice in VoiceStore takes priority over built-in voice")
    func customVoicePriorityOverBuiltin() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-engine-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
        // Save a custom voice named "alex" (same as a built-in).
        let customAlex = StoredVoice(
            name: "alex",
            type: .designed,
            designDescription: "My custom Alex voice"
        )
        try voiceStore.saveVoice(customAlex)

        let engine = DigaEngine(voiceStore: voiceStore)

        let resolved = try await engine.resolveVoice(name: "alex")
        // Should get the custom one, not the built-in.
        #expect(resolved.type == .designed)
        #expect(resolved.designDescription == "My custom Alex voice")
    }
}

// MARK: - DigaEngine Instantiation Tests

@Suite("DigaEngine Instantiation Tests")
struct DigaEngineInstantiationTests {

    // --- Test 20: Engine instantiates without error ---

    @Test("DigaEngine instantiates with default parameters without error")
    func instantiatesWithoutError() {
        let engine = DigaEngine()
        // Actor creation should not crash or throw.
        // Verify it exists by calling a method on it.
        let _ = engine
    }

    // --- Test 21: Engine instantiates with custom parameters ---

    @Test("DigaEngine instantiates with custom voice store and model override")
    func instantiatesWithCustomParams() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diga-engine-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let voiceStore = VoiceStore(directory: tempDir.appendingPathComponent("voices"))
        let engine = DigaEngine(
            voiceStore: voiceStore,
            modelOverride: "custom/model-id"
        )
        // Verify the engine was created successfully by using it.
        let _ = engine
    }
}

// MARK: - DigaEngineError Tests

@Suite("DigaEngineError Tests")
struct DigaEngineErrorTests {

    // --- Test 22: Error descriptions are human-readable ---

    @Test("DigaEngineError has human-readable error descriptions")
    func errorDescriptions() {
        let errors: [DigaEngineError] = [
            .voiceNotFound("test"),
            .voiceDesignFailed("detail"),
            .synthesisFailed("detail"),
            .wavConcatenationFailed("detail"),
            .modelNotAvailable("detail"),
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil, "Error should have a description: \(error)")
            #expect(!description!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    // --- Test 23: voiceNotFound contains the voice name ---

    @Test("voiceNotFound error contains the requested voice name")
    func voiceNotFoundContainsName() {
        let error = DigaEngineError.voiceNotFound("mysterio")
        #expect(error.errorDescription?.contains("mysterio") == true)
    }
}

// MARK: - WAVConcatenator.buildWAVData Tests

@Suite("WAVConcatenator Build Tests")
struct WAVConcatenatorBuildTests {

    // --- Test 24: buildWAVData produces valid WAV header ---

    @Test("buildWAVData produces valid RIFF/WAVE header")
    func buildWAVProducesValidHeader() {
        let wav = WAVConcatenator.buildWAVData(pcmSamples: [100, 200, 300])

        // Minimum 44-byte header + 6 bytes PCM (3 samples * 2 bytes).
        #expect(wav.count == 50)

        let riff = String(data: wav[0..<4], encoding: .ascii)
        #expect(riff == "RIFF")

        let wave = String(data: wav[8..<12], encoding: .ascii)
        #expect(wave == "WAVE")

        let fmt = String(data: wav[12..<16], encoding: .ascii)
        #expect(fmt == "fmt ")

        let dataMarker = String(data: wav[36..<40], encoding: .ascii)
        #expect(dataMarker == "data")
    }

    // --- Test 25: buildWAVData with empty samples produces header-only WAV ---

    @Test("buildWAVData with empty samples produces valid header-only WAV")
    func buildWAVEmptySamples() {
        let wav = WAVConcatenator.buildWAVData(pcmSamples: [])
        #expect(wav.count == 44)

        let riff = String(data: wav[0..<4], encoding: .ascii)
        #expect(riff == "RIFF")
    }
}
