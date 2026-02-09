import Foundation

// MARK: - DigaEngineError

/// Errors specific to the diga synthesis engine.
enum DigaEngineError: Error, LocalizedError, Sendable {
    /// The requested voice name was not found in custom voices or built-in voices.
    case voiceNotFound(String)

    /// Voice design failed during lazy generation of a built-in voice's clone prompt.
    case voiceDesignFailed(String)

    /// Synthesis failed for a text chunk.
    case synthesisFailed(String)

    /// WAV concatenation or audio assembly failed.
    case wavConcatenationFailed(String)

    /// The engine's model is not available or could not be loaded.
    case modelNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .voiceNotFound(let name):
            return "Voice '\(name)' not found. Use --voices to list available voices, or --design / --clone to create one."
        case .voiceDesignFailed(let detail):
            return "Voice design failed: \(detail)"
        case .synthesisFailed(let detail):
            return "Synthesis failed: \(detail)"
        case .wavConcatenationFailed(let detail):
            return "WAV concatenation failed: \(detail)"
        case .modelNotAvailable(let detail):
            return "Model not available: \(detail)"
        }
    }
}

// MARK: - WAV Helpers

/// Utilities for building and concatenating WAV PCM audio data.
enum WAVConcatenator: Sendable {

    /// Standard WAV header size for the format produced by `buildWAVData`.
    /// 12 bytes RIFF header + 24 bytes fmt chunk (8 header + 16 data) + 8 bytes data chunk header = 44.
    static let standardHeaderSize = 44

    /// Build a complete WAV file Data from 16-bit PCM samples.
    ///
    /// This is a self-contained WAV builder for the diga module, producing the
    /// same format as `AudioConversion.buildWAVData` in the SwiftVoxAlta library
    /// (mono, 16-bit PCM, RIFF/WAVE container).
    ///
    /// - Parameters:
    ///   - pcmSamples: Array of 16-bit PCM integer samples.
    ///   - sampleRate: Sample rate in Hz. Defaults to 24000.
    /// - Returns: Complete WAV format Data with RIFF header.
    static func buildWAVData(pcmSamples: [Int16], sampleRate: Int = 24000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = numChannels * bytesPerSample
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcmSamples.count * Int(bytesPerSample))
        let fileSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(standardHeaderSize + Int(dataSize))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendLE(&data, fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendLE(&data, UInt32(16))          // fmt chunk size
        appendLE(&data, UInt16(1))            // PCM format
        appendLE(&data, numChannels)
        appendLE(&data, UInt32(sampleRate))
        appendLE(&data, byteRate)
        appendLE(&data, blockAlign)
        appendLE(&data, bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendLE(&data, dataSize)

        // PCM samples
        for sample in pcmSamples {
            appendLE(&data, UInt16(bitPattern: sample))
        }

        return data
    }

    /// Concatenate multiple WAV Data segments (each with a standard 44-byte header)
    /// into a single WAV Data with one header covering all raw PCM samples.
    ///
    /// All inputs must be mono, 16-bit PCM WAV files with the standard
    /// 44-byte header format produced by `buildWAVData`.
    ///
    /// - Parameters:
    ///   - wavSegments: An array of WAV Data objects to concatenate.
    ///   - sampleRate: The sample rate of all segments. Defaults to 24000.
    /// - Returns: A single WAV Data containing all PCM samples with one header.
    /// - Throws: `DigaEngineError.wavConcatenationFailed` if any segment is too short.
    static func concatenate(_ wavSegments: [Data], sampleRate: Int = 24000) throws -> Data {
        guard !wavSegments.isEmpty else {
            throw DigaEngineError.wavConcatenationFailed("No WAV segments to concatenate.")
        }

        // If there's only one segment, return it as-is.
        if wavSegments.count == 1 {
            return wavSegments[0]
        }

        // Extract raw PCM data (skip 44-byte header) from each segment.
        var rawPCMData = Data()
        for (index, segment) in wavSegments.enumerated() {
            guard segment.count > standardHeaderSize else {
                throw DigaEngineError.wavConcatenationFailed(
                    "WAV segment \(index) is too short (\(segment.count) bytes). Expected at least \(standardHeaderSize + 1) bytes."
                )
            }
            rawPCMData.append(segment[standardHeaderSize...])
        }

        // Build a new WAV header for the combined data.
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = numChannels * bytesPerSample
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(rawPCMData.count)
        let fileSize = 36 + dataSize

        var header = Data()
        header.reserveCapacity(standardHeaderSize)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        appendLE(&header, fileSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        appendLE(&header, UInt32(16))         // fmt chunk size
        appendLE(&header, UInt16(1))           // PCM format
        appendLE(&header, numChannels)
        appendLE(&header, UInt32(sampleRate))
        appendLE(&header, byteRate)
        appendLE(&header, blockAlign)
        appendLE(&header, bitsPerSample)

        // data chunk header
        header.append(contentsOf: "data".utf8)
        appendLE(&header, dataSize)

        // Combine header + raw PCM
        var result = header
        result.append(rawPCMData)
        return result
    }

    /// Append a fixed-width integer in little-endian byte order.
    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        data.append(Data(bytes: &le, count: MemoryLayout<T>.size))
    }
}

// MARK: - DigaEngine

/// Actor that orchestrates model loading, voice resolution, and text-to-speech synthesis.
///
/// `DigaEngine` coordinates `DigaModelManager` for TTS model availability,
/// `VoiceStore` for custom voice persistence, and `BuiltinVoices` for shipped
/// voice definitions. Text is chunked into sentence-bounded segments via
/// `TextChunker`, synthesized sequentially, and concatenated into a single WAV output.
///
/// Standard pacing and emotion parameters are hardcoded internally -- this actor
/// provides a simple `synthesize(text:voiceName:)` entry point.
actor DigaEngine {

    // MARK: - Properties

    /// Manages TTS model downloads and availability checks.
    private let modelManager: DigaModelManager

    /// Persists custom voice definitions to disk.
    private let voiceStore: VoiceStore

    /// Override model ID (from --model flag), or nil for auto-selection.
    private let modelOverride: String?

    // MARK: - Initialization

    /// Creates a new DigaEngine.
    ///
    /// - Parameters:
    ///   - modelManager: Model manager for download/availability. Defaults to standard instance.
    ///   - voiceStore: Voice store for custom voices. Defaults to standard instance.
    ///   - modelOverride: Optional model ID override (from --model flag).
    init(
        modelManager: DigaModelManager = DigaModelManager(),
        voiceStore: VoiceStore = VoiceStore(),
        modelOverride: String? = nil
    ) {
        self.modelManager = modelManager
        self.voiceStore = voiceStore
        self.modelOverride = modelOverride
    }

    // MARK: - Voice Resolution

    /// Resolve a voice name to a `StoredVoice` with clone prompt data.
    ///
    /// Resolution order:
    /// 1. Check `VoiceStore` for a custom voice with a clone prompt on disk.
    /// 2. Check `BuiltinVoices` -- if found and this is the first use, the clone prompt
    ///    would be lazily generated via VoiceDesign and cached. (In the current implementation,
    ///    the built-in voice entry is returned; actual VoiceDesign generation is deferred
    ///    to synthesis time when model loading is fully wired.)
    /// 3. If no name is provided, use the first built-in voice as default.
    ///
    /// - Parameter name: The voice name to resolve, or `nil` for the default voice.
    /// - Returns: The resolved `StoredVoice`.
    /// - Throws: `DigaEngineError.voiceNotFound` if the name matches no known voice.
    func resolveVoice(name: String?) throws -> StoredVoice {
        // Default to first built-in voice if no name specified.
        guard let voiceName = name else {
            let builtins = BuiltinVoices.all()
            guard let first = builtins.first else {
                throw DigaEngineError.voiceNotFound("(default)")
            }
            return first
        }

        // 1. Check custom voices in VoiceStore.
        if let custom = try voiceStore.getVoice(name: voiceName) {
            return custom
        }

        // 2. Check built-in voices.
        if let builtin = BuiltinVoices.get(name: voiceName) {
            return builtin
        }

        // 3. Not found anywhere.
        throw DigaEngineError.voiceNotFound(voiceName)
    }

    /// Load the clone prompt data for a resolved voice.
    ///
    /// For custom voices with a `clonePromptPath`, reads the file from disk.
    /// For built-in voices on first use, this would run VoiceDesign to generate
    /// the clone prompt and cache it. Currently returns nil for built-in voices
    /// to signal that lazy generation is needed.
    ///
    /// - Parameter voice: The resolved `StoredVoice`.
    /// - Returns: Clone prompt data, or nil if the voice needs lazy generation.
    func loadClonePromptData(for voice: StoredVoice) throws -> Data? {
        // If there's a clone prompt file on disk, load it.
        if let promptPath = voice.clonePromptPath {
            let promptURL: URL
            if promptPath.hasPrefix("/") || promptPath.hasPrefix("~") {
                promptURL = URL(fileURLWithPath: promptPath)
            } else {
                promptURL = voiceStore.voicesDirectory.appendingPathComponent(promptPath)
            }

            if FileManager.default.fileExists(atPath: promptURL.path) {
                return try Data(contentsOf: promptURL)
            }
        }

        // For built-in voices, a clone prompt is generated lazily on first use.
        // Return nil to signal lazy generation is needed.
        return nil
    }

    // MARK: - Synthesis

    /// Synthesize speech from text using the specified voice.
    ///
    /// The text is split into sentence-bounded chunks of ~200 words, each chunk
    /// is synthesized sequentially, and the resulting WAV segments are concatenated
    /// into a single WAV output (24kHz, 16-bit PCM, mono).
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceName: The voice name to use, or nil for the default voice.
    /// - Returns: WAV format audio Data.
    /// - Throws: `DigaEngineError` if voice resolution, model loading, or synthesis fails.
    func synthesize(text: String, voiceName: String? = nil) async throws -> Data {
        // Resolve voice.
        let voice = try resolveVoice(name: voiceName)

        // Ensure model is available.
        try await ensureModelAvailable()

        // Chunk the text.
        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else {
            throw DigaEngineError.synthesisFailed("Input text is empty after chunking.")
        }

        // Synthesize each chunk sequentially.
        // NOTE: Actual TTS generation requires loading the Qwen3 model and using
        // clone prompts. This is the orchestration skeleton — the actual model
        // inference call will be wired when the mlx-audio-swift fork is complete.
        var wavSegments: [Data] = []
        for chunk in chunks {
            let wavData = try await synthesizeChunk(chunk, voice: voice)
            wavSegments.append(wavData)
        }

        // Concatenate all WAV segments into a single output.
        return try WAVConcatenator.concatenate(wavSegments)
    }

    // MARK: - Private

    /// Ensure the TTS model is downloaded and available.
    private func ensureModelAvailable() async throws {
        let modelId: String
        if let override = modelOverride {
            modelId = override
        } else {
            modelId = modelManager.recommendedModel()
        }

        let available = await modelManager.isModelAvailable(modelId)
        if !available {
            throw DigaEngineError.modelNotAvailable(
                "Model \(modelId) is not downloaded. Run `diga` first to trigger download."
            )
        }
    }

    /// Synthesize a single text chunk to WAV data.
    ///
    /// This is the per-chunk synthesis call. In the full implementation, this would:
    /// 1. Deserialize the clone prompt for the resolved voice
    /// 2. Call `Qwen3TTSModel.generate()` with the text and clone prompt
    /// 3. Convert the MLXArray output to WAV Data
    ///
    /// Currently produces a silent WAV placeholder of appropriate duration,
    /// since actual model inference requires the mlx-audio-swift fork.
    private func synthesizeChunk(_ text: String, voice: StoredVoice) async throws -> Data {
        // Estimate duration: ~150 words per minute.
        let wordCount = TextChunker.wordCount(text)
        let durationSeconds = Double(wordCount) / 150.0 * 60.0
        let sampleRate = 24000
        let sampleCount = Int(durationSeconds * Double(sampleRate))

        // Generate silent PCM samples (placeholder until real model inference is wired).
        let silentSamples = [Int16](repeating: 0, count: max(sampleCount, 1))
        return WAVConcatenator.buildWAVData(pcmSamples: silentSamples, sampleRate: sampleRate)
    }
}
