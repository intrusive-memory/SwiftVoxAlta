import AVFoundation
import Foundation
import Testing
@testable import diga

// MARK: - WAVHeaderParser Tests

@Suite("WAVHeaderParser Tests")
struct WAVHeaderParserTests {

    /// Helper: build a known WAV using the engine's WAVConcatenator.
    private func makeTestWAV(
        samples: [Int16] = [100, -200, 300, -400],
        sampleRate: Int = 24000
    ) -> Data {
        WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: sampleRate)
    }

    // --- Test 1: Parse valid WAV header ---

    @Test("Parse valid WAV header extracts correct parameters")
    func parseValidWAVHeader() throws {
        let wav = makeTestWAV(samples: [100, -200, 300], sampleRate: 24000)
        let header = try WAVHeaderParser.parse(wav)

        #expect(header.sampleRate == 24000)
        #expect(header.numChannels == 1)
        #expect(header.bitsPerSample == 16)
        #expect(header.dataOffset == 44)
        #expect(header.dataSize == 6) // 3 samples * 2 bytes
    }

    // --- Test 2: Data too short throws ---

    @Test("Data shorter than 44 bytes throws invalidWAVData")
    func tooShortDataThrows() {
        let shortData = Data(repeating: 0, count: 20)
        #expect(throws: AudioPlaybackError.self) {
            try WAVHeaderParser.parse(shortData)
        }
    }

    // --- Test 3: Missing RIFF marker throws ---

    @Test("Data without RIFF marker throws invalidWAVData")
    func missingRIFFThrows() {
        var data = makeTestWAV()
        // Corrupt the RIFF marker
        data[0] = 0x00
        #expect(throws: AudioPlaybackError.self) {
            try WAVHeaderParser.parse(data)
        }
    }
}

// MARK: - AudioPlayback PCM Buffer Tests

@Suite("AudioPlayback PCM Buffer Tests")
struct AudioPlaybackPCMBufferTests {

    /// Helper: build a known WAV using the engine's WAVConcatenator.
    private func makeTestWAV(
        samples: [Int16] = [100, -200, 300, -400],
        sampleRate: Int = 24000
    ) -> Data {
        WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: sampleRate)
    }

    // --- Test 4: AudioPlayback initializes without error (create buffer from valid WAV) ---

    @Test("AudioPlayback can create PCM buffer from valid WAV data")
    func createPCMBufferFromValidWAV() throws {
        let samples: [Int16] = [1000, -2000, 3000, -4000, 5000]
        let wav = makeTestWAV(samples: samples, sampleRate: 24000)

        let (format, buffer) = try AudioPlayback.createPCMBuffer(from: wav)

        #expect(format.sampleRate == 24000.0)
        #expect(format.channelCount == 1)
        #expect(buffer.frameLength == 5)
    }

    // --- Test 5: PCM buffer float samples match expected normalization ---

    @Test("PCM buffer contains correctly normalized float samples")
    func pcmBufferNormalization() throws {
        // Int16.max = 32767, Int16.min = -32768
        let samples: [Int16] = [0, 16384, -16384, 32767, -32768]
        let wav = makeTestWAV(samples: samples, sampleRate: 24000)

        let (_, buffer) = try AudioPlayback.createPCMBuffer(from: wav)

        guard let floatData = buffer.floatChannelData else {
            Issue.record("floatChannelData is nil")
            return
        }

        let channel0 = floatData[0]

        // Sample 0: 0 / 32768.0 = 0.0
        #expect(abs(channel0[0] - 0.0) < 0.001)

        // Sample 1: 16384 / 32768.0 = 0.5
        #expect(abs(channel0[1] - 0.5) < 0.001)

        // Sample 2: -16384 / 32768.0 = -0.5
        #expect(abs(channel0[2] - (-0.5)) < 0.001)

        // Sample 3: 32767 / 32768.0 ~ 0.99997
        #expect(abs(channel0[3] - 0.99997) < 0.001)

        // Sample 4: -32768 / 32768.0 = -1.0
        #expect(abs(channel0[4] - (-1.0)) < 0.001)
    }

    // --- Test 6: Creating buffer from invalid WAV throws ---

    @Test("Creating PCM buffer from invalid data throws")
    func createBufferFromInvalidDataThrows() {
        let garbage = Data(repeating: 0xFF, count: 100)
        #expect(throws: AudioPlaybackError.self) {
            try AudioPlayback.createPCMBuffer(from: garbage)
        }
    }

    // --- Test 7: Creating buffer from WAV with zero PCM data throws ---

    @Test("Creating PCM buffer from WAV with zero data size throws")
    func createBufferFromEmptyPCMThrows() {
        let wav = WAVConcatenator.buildWAVData(pcmSamples: [], sampleRate: 24000)
        #expect(throws: AudioPlaybackError.self) {
            try AudioPlayback.createPCMBuffer(from: wav)
        }
    }

    // --- Test 8: Multiple buffers from sequential chunks have matching formats ---

    @Test("Multiple PCM buffers from sequential chunks share the same format")
    func sequentialChunksMatchFormats() throws {
        let wav1 = makeTestWAV(samples: [100, 200, 300], sampleRate: 24000)
        let wav2 = makeTestWAV(samples: [400, 500, 600], sampleRate: 24000)

        let (format1, buffer1) = try AudioPlayback.createPCMBuffer(from: wav1)
        let (format2, buffer2) = try AudioPlayback.createPCMBuffer(from: wav2)

        #expect(format1.sampleRate == format2.sampleRate)
        #expect(format1.channelCount == format2.channelCount)
        #expect(buffer1.frameLength == 3)
        #expect(buffer2.frameLength == 3)
    }
}

// MARK: - AudioPlaybackError Tests

@Suite("AudioPlaybackError Tests")
struct AudioPlaybackErrorTests {

    // --- Test 9: Error descriptions are non-empty ---

    @Test("AudioPlaybackError has human-readable error descriptions")
    func errorDescriptions() {
        let errors: [AudioPlaybackError] = [
            .invalidWAVData("test"),
            .unsupportedFormat("test"),
            .bufferCreationFailed("test"),
            .engineStartFailed("test"),
            .playbackFailed("test"),
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil, "Error should have a description: \(error)")
            #expect(!description!.isEmpty, "Error description should not be empty: \(error)")
        }
    }
}

// MARK: - CompletionCounter Tests (via streaming path validation)

@Suite("AudioPlayback Streaming Tests")
struct AudioPlaybackStreamingTests {

    /// Helper: build a known WAV using the engine's WAVConcatenator.
    private func makeTestWAV(
        samples: [Int16] = [100, -200, 300, -400],
        sampleRate: Int = 24000
    ) -> Data {
        WAVConcatenator.buildWAVData(pcmSamples: samples, sampleRate: sampleRate)
    }

    // --- Test 10: Streaming playback with empty stream completes without error ---

    @Test("Streaming playback with empty stream completes immediately")
    func emptyStreamCompletes() async throws {
        let stream = AsyncStream<Data> { continuation in
            continuation.finish()
        }

        // playChunks with an empty stream should return without error
        // and without attempting to start the audio engine.
        try await AudioPlayback.playChunks(chunks: stream)
    }

    // --- Test 11: Two sequential chunks produce valid buffers ---

    @Test("Two sequential WAV chunks produce valid PCM buffers with correct frame counts")
    func twoChunksProduceValidBuffers() throws {
        let samples1: [Int16] = [100, 200, 300, 400, 500]
        let samples2: [Int16] = [600, 700, 800, 900, 1000]

        let wav1 = makeTestWAV(samples: samples1, sampleRate: 24000)
        let wav2 = makeTestWAV(samples: samples2, sampleRate: 24000)

        let (format1, buffer1) = try AudioPlayback.createPCMBuffer(from: wav1)
        let (format2, buffer2) = try AudioPlayback.createPCMBuffer(from: wav2)

        // Both chunks should parse successfully with matching formats.
        #expect(format1.sampleRate == format2.sampleRate)
        #expect(format1.channelCount == format2.channelCount)

        // Both should have 5 frames each.
        #expect(buffer1.frameLength == 5)
        #expect(buffer2.frameLength == 5)

        // Combined playback duration would be 10 frames at 24kHz.
        let totalFrames = buffer1.frameLength + buffer2.frameLength
        let totalDuration = Double(totalFrames) / format1.sampleRate
        #expect(totalDuration > 0)
    }
}

// MARK: - DigaCommand Input Routing Tests

@Suite("DigaCommand Input Routing Tests")
struct DigaCommandInputRoutingTests {

    // --- Test 12: Command with positional text args triggers synthesis path ---

    @Test("Command with positional text arguments populates positionalArgs")
    func positionalArgsPopulated() throws {
        // Verify that ArgumentParser correctly parses positional arguments
        // that would trigger the synthesis/playback path.
        var command = try DigaCommand.parse(["hello", "world"])

        #expect(command.positionalArgs == ["hello", "world"])
        #expect(command.file == nil)
        #expect(command.output == nil)
        #expect(command.voices == false)
    }

    // --- Test 13: Command with -f flag parses file path ---

    @Test("Command with -f flag parses file path correctly")
    func fileFlagParsed() throws {
        let command = try DigaCommand.parse(["-f", "/tmp/input.txt"])

        #expect(command.file == "/tmp/input.txt")
        #expect(command.positionalArgs.isEmpty)
    }

    // --- Test 14: Command with -o flag parses output path ---

    @Test("Command with -o flag parses output path correctly")
    func outputFlagParsed() throws {
        let command = try DigaCommand.parse(["-o", "/tmp/output.wav", "hello"])

        #expect(command.output == "/tmp/output.wav")
        #expect(command.positionalArgs == ["hello"])
    }

    // --- Test 15: Command with -v flag parses voice name ---

    @Test("Command with -v flag parses voice name correctly")
    func voiceFlagParsed() throws {
        let command = try DigaCommand.parse(["-v", "alex", "hello", "world"])

        #expect(command.voice == "alex")
        #expect(command.positionalArgs == ["hello", "world"])
    }
}
