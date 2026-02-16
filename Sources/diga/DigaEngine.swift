import Foundation
@preconcurrency import SwiftVoxAlta
@preconcurrency import MLX
@preconcurrency import MLXAudioTTS
@preconcurrency import MLXLMCommon
import VoxFormat

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

/// Actor that orchestrates model loading, voice resolution, and text-to-speech synthesis
/// using Qwen3-TTS via the SwiftVoxAlta library.
///
/// `DigaEngine` coordinates `VoxAltaModelManager` for TTS model loading,
/// `VoiceStore` for custom voice persistence, and `BuiltinVoices` for shipped
/// voice definitions. Text is chunked into sentence-bounded segments via
/// `TextChunker`, synthesized sequentially via `VoiceLockManager`, and
/// concatenated into a single WAV output.
actor DigaEngine {

    // MARK: - Properties

    /// Manages TTS model downloads and availability checks (used for pre-flight checks).
    private let modelManager: DigaModelManager

    /// Persists custom voice definitions to disk.
    private let voiceStore: VoiceStore

    /// Override model ID (from --model flag), or nil for auto-selection.
    private let modelOverride: String?

    /// VoxAlta model manager for loading Qwen3-TTS models into memory.
    private let voxAltaModelManager: VoxAltaModelManager

    /// Cached clone prompt data for the current voice (avoids re-reading from disk).
    private var cachedClonePromptData: Data?

    /// Name of the voice whose clone prompt is cached.
    private var cachedVoiceName: String?

    // MARK: - Initialization

    /// Creates a new DigaEngine.
    ///
    /// - Parameters:
    ///   - voiceStore: Voice store for custom voices. Defaults to standard instance.
    ///   - modelOverride: Optional model ID override (from --model flag).
    ///   - voxAltaModelManager: VoxAlta model manager for TTS inference. Defaults to a new instance.
    init(
        voiceStore: VoiceStore = VoiceStore(),
        modelOverride: String? = nil,
        voxAltaModelManager: VoxAltaModelManager = VoxAltaModelManager()
    ) {
        self.modelManager = DigaModelManager()
        self.voiceStore = voiceStore
        self.modelOverride = modelOverride
        self.voxAltaModelManager = voxAltaModelManager
    }

    // MARK: - Model Resolution

    /// Resolves the model override string to a `Qwen3TTSModelRepo` for clone-prompt synthesis.
    ///
    /// If `modelOverride` is set and matches a known model ID, returns that variant.
    /// Otherwise defaults to `.base1_7B` because clone prompt extraction and
    /// clone-prompt-based generation require the Base model (not CustomVoice).
    /// Preset speaker paths bypass this and use CustomVoice directly.
    private var resolvedBaseModelRepo: Qwen3TTSModelRepo {
        guard let override = modelOverride else { return .base1_7B }
        if let match = Qwen3TTSModelRepo(rawValue: override) {
            return match
        }
        // Map shorthands: the DigaCommand already resolves 0.6b/1.7b to full IDs,
        // so we check the full ID against known repos.
        if override == TTSModelID.small {
            return .base0_6B
        }
        // Default to Base 1.7B for unknown overrides
        return .base1_7B
    }

    // MARK: - Voice Resolution

    /// Resolve a voice name to a `StoredVoice`.
    ///
    /// Resolution order:
    /// 1. Check `VoiceStore` for a custom voice.
    /// 2. Check `BuiltinVoices`.
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

    // MARK: - Synthesis

    /// Synthesize speech from text using the specified voice.
    ///
    /// The text is split into sentence-bounded chunks, each chunk is synthesized
    /// using Qwen3-TTS via the Base model with the voice's clone prompt, and
    /// the resulting WAV segments are concatenated into a single WAV output
    /// (24kHz, 16-bit PCM, mono).
    ///
    /// On first use of a built-in or designed voice, the VoiceDesign model generates
    /// a reference audio clip, from which a clone prompt is extracted and cached to disk.
    /// Subsequent uses load the cached clone prompt directly.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceName: The voice name to use, or nil for the default voice.
    /// - Returns: WAV format audio Data.
    /// - Throws: `DigaEngineError` if voice resolution, model loading, or synthesis fails.
    func synthesize(text: String, voiceName: String? = nil) async throws -> Data {
        // Resolve voice.
        let voice = try resolveVoice(name: voiceName)

        // For preset voices, use speaker name directly (no clone prompt needed).
        if voice.type == .preset, let speakerName = voice.clonePromptPath {
            return try await synthesizeWithPresetSpeaker(
                text: text,
                speakerName: speakerName,
                voiceName: voice.name,
                modelManager: voxAltaModelManager,
                modelRepo: .customVoice1_7B
            )
        }

        // Load or generate clone prompt for this voice.
        let clonePromptData = try await loadOrCreateClonePrompt(for: voice)

        // Build a VoiceLock for generation.
        let voiceLock = VoiceLock(
            characterName: voice.name,
            clonePromptData: clonePromptData,
            designInstruction: voice.designDescription ?? ""
        )

        // Chunk the text.
        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else {
            throw DigaEngineError.synthesisFailed("Input text is empty after chunking.")
        }

        // Synthesize each chunk sequentially.
        if chunks.count > 1 {
            FileHandle.standardError.write(Data("Synthesizing \(chunks.count) chunks...\n".utf8))
        }

        var wavSegments: [Data] = []
        for (i, chunk) in chunks.enumerated() {
            if chunks.count > 1 {
                FileHandle.standardError.write(Data("\rChunk \(i + 1)/\(chunks.count)...".utf8))
            }

            let wavData: Data
            do {
                let context = GenerationContext(phrase: chunk)
                wavData = try await VoiceLockManager.generateAudio(
                    context: context,
                    voiceLock: voiceLock,
                    language: "en",
                    modelManager: voxAltaModelManager,
                    modelRepo: resolvedBaseModelRepo
                )
            } catch {
                throw DigaEngineError.synthesisFailed(
                    "Failed to synthesize chunk \(i + 1): \(error.localizedDescription)"
                )
            }
            wavSegments.append(wavData)
        }

        if chunks.count > 1 {
            FileHandle.standardError.write(Data("\n".utf8))
        }

        // Concatenate all WAV segments into a single output.
        return try WAVConcatenator.concatenate(wavSegments)
    }

    /// Synthesize speech directly from a `.vox` file without requiring import.
    ///
    /// The `.vox` file is read and its contents are used to drive synthesis:
    /// - If a clone prompt is embedded, it is used directly.
    /// - If reference audio is present (but no clone prompt), a clone prompt is extracted.
    /// - If only a description is available, VoiceDesign generates a voice.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voxPath: Path to the `.vox` file.
    /// - Returns: WAV format audio Data.
    /// - Throws: `DigaEngineError` if import, voice resolution, or synthesis fails.
    func synthesizeFromVox(text: String, voxPath: String) async throws -> Data {
        let voxURL = URL(fileURLWithPath: voxPath)
        let importResult: VoxImportResult
        do {
            importResult = try VoxImporter.importVox(from: voxURL)
        } catch {
            throw DigaEngineError.synthesisFailed("Failed to read .vox file: \(error.localizedDescription)")
        }

        let clonePromptData: Data

        if let promptData = importResult.clonePromptData {
            // Clone prompt embedded — use directly.
            clonePromptData = promptData
        } else if let firstRefData = importResult.referenceAudio.values.first {
            // Reference audio available — extract clone prompt.
            FileHandle.standardError.write(
                Data("Extracting clone prompt from reference audio...\n".utf8)
            )
            let refData = firstRefData
            let lock = try await VoiceLockManager.createLock(
                characterName: importResult.name,
                candidateAudio: refData,
                designInstruction: importResult.description,
                modelManager: voxAltaModelManager,
                modelRepo: resolvedBaseModelRepo
            )
            clonePromptData = lock.clonePromptData
        } else {
            // No clone prompt or reference audio — use VoiceDesign.
            FileHandle.standardError.write(
                Data("Generating voice from description (first use)...\n".utf8)
            )
            let profile = CharacterProfile(
                name: importResult.name,
                gender: .unknown,
                ageRange: "",
                description: importResult.description,
                voiceTraits: [],
                summary: importResult.description
            )
            let candidateAudio = try await VoiceDesigner.generateCandidate(
                profile: profile,
                modelManager: voxAltaModelManager
            )
            let lock = try await VoiceLockManager.createLock(
                characterName: importResult.name,
                candidateAudio: candidateAudio,
                designInstruction: importResult.description,
                modelManager: voxAltaModelManager,
                modelRepo: resolvedBaseModelRepo
            )
            clonePromptData = lock.clonePromptData
        }

        let voiceLock = VoiceLock(
            characterName: importResult.name,
            clonePromptData: clonePromptData,
            designInstruction: importResult.description
        )

        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else {
            throw DigaEngineError.synthesisFailed("Input text is empty after chunking.")
        }

        if chunks.count > 1 {
            FileHandle.standardError.write(Data("Synthesizing \(chunks.count) chunks...\n".utf8))
        }

        var wavSegments: [Data] = []
        for (i, chunk) in chunks.enumerated() {
            if chunks.count > 1 {
                FileHandle.standardError.write(Data("\rChunk \(i + 1)/\(chunks.count)...".utf8))
            }
            let context = GenerationContext(phrase: chunk)
            let wavData = try await VoiceLockManager.generateAudio(
                context: context,
                voiceLock: voiceLock,
                language: "en",
                modelManager: voxAltaModelManager,
                modelRepo: resolvedBaseModelRepo
            )
            wavSegments.append(wavData)
        }

        if chunks.count > 1 {
            FileHandle.standardError.write(Data("\n".utf8))
        }

        return try WAVConcatenator.concatenate(wavSegments)
    }

    /// Synthesize speech using a CustomVoice preset speaker.
    ///
    /// Preset speakers bypass the clone prompt generation flow entirely.
    /// The speaker name (e.g., "ryan", "aiden", "ono_anna") is passed directly
    /// to the Qwen3-TTS CustomVoice model for generation.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - speakerName: The CustomVoice speaker name.
    ///   - voiceName: The user-facing voice name (for logging).
    ///   - modelManager: The model manager used to load the CustomVoice model.
    ///   - modelRepo: The CustomVoice model variant to use. Defaults to `.customVoice1_7B`.
    /// - Returns: WAV format audio Data.
    /// - Throws: `DigaEngineError` if model loading or synthesis fails.
    nonisolated private func synthesizeWithPresetSpeaker(
        text: String,
        speakerName: String,
        voiceName: String,
        modelManager: VoxAltaModelManager,
        modelRepo: Qwen3TTSModelRepo
    ) async throws -> Data {
        // 1. Chunk text.
        let chunks = TextChunker.chunk(text)
        guard !chunks.isEmpty else {
            throw DigaEngineError.synthesisFailed("Input text is empty after chunking.")
        }

        if chunks.count > 1 {
            FileHandle.standardError.write(Data("Synthesizing \(chunks.count) chunks...\n".utf8))
        }

        // 2. Generate each chunk with CustomVoice speaker.
        var wavSegments: [Data] = []
        for (i, chunk) in chunks.enumerated() {
            if chunks.count > 1 {
                FileHandle.standardError.write(Data("\rChunk \(i + 1)/\(chunks.count)...".utf8))
            }

            // Load model and generate
            let audioArray: MLXArray
            let sampleRate: Int
            do {
                let model = try await modelManager.loadModel(modelRepo)
                guard let qwenModel = model as? Qwen3TTSModel else {
                    throw DigaEngineError.synthesisFailed("Not a Qwen3TTSModel")
                }

                // Use high-level generate() API which routes to CustomVoice path
                audioArray = try await qwenModel.generate(
                    text: chunk,
                    voice: speakerName,
                    refAudio: nil,
                    refText: nil,
                    language: "en",
                    generationParameters: GenerateParameters()
                )
                sampleRate = qwenModel.sampleRate
            } catch {
                throw DigaEngineError.synthesisFailed(
                    "Failed to synthesize chunk \(i + 1): \(error.localizedDescription)"
                )
            }

            let wavData = try AudioConversion.mlxArrayToWAVData(
                audioArray,
                sampleRate: sampleRate
            )
            wavSegments.append(wavData)
        }

        if chunks.count > 1 {
            FileHandle.standardError.write(Data("\n".utf8))
        }

        // 3. Concatenate WAV segments.
        return try WAVConcatenator.concatenate(wavSegments)
    }

    // MARK: - Clone Prompt Management

    /// Load or create a clone prompt for the given voice.
    ///
    /// Checks (in order):
    /// 1. In-memory cache
    /// 2. On-disk cache (`~/.diga/voices/<name>.cloneprompt`)
    /// 3. Generate from scratch:
    ///    - Cloned voices: create clone prompt from reference audio file
    ///    - Built-in/designed voices: run VoiceDesign to generate reference clip,
    ///      then extract clone prompt from it
    ///
    /// Generated clone prompts are saved to disk for future reuse.
    ///
    /// - Parameter voice: The resolved `StoredVoice`.
    /// - Returns: Serialized clone prompt data.
    /// - Throws: `DigaEngineError` if clone prompt creation fails.
    func loadOrCreateClonePrompt(for voice: StoredVoice) async throws -> Data {
        // 1. Check in-memory cache.
        if let cached = cachedClonePromptData, cachedVoiceName == voice.name {
            return cached
        }

        // 2. Check on-disk cache.
        let promptFile = voiceStore.voicesDirectory
            .appendingPathComponent("\(voice.name).cloneprompt")
        if FileManager.default.fileExists(atPath: promptFile.path) {
            let data = try Data(contentsOf: promptFile)
            cachedClonePromptData = data
            cachedVoiceName = voice.name
            return data
        }

        // 3. Generate clone prompt.
        let clonePromptData: Data

        if voice.type == .cloned, let refPath = voice.clonePromptPath {
            // Cloned voice: create clone prompt from reference audio.
            let refURL: URL
            if refPath.hasPrefix("/") || refPath.hasPrefix("~") {
                refURL = URL(fileURLWithPath: refPath)
            } else {
                refURL = voiceStore.voicesDirectory.appendingPathComponent(refPath)
            }

            // Auto-generate reference audio if it doesn't exist
            if !FileManager.default.fileExists(atPath: refURL.path) {
                FileHandle.standardError.write(
                    Data("Generating reference audio for '\(voice.name)' (first use)...\n".utf8)
                )
                do {
                    try ReferenceAudioGenerator.generate(
                        voiceName: voice.name,
                        outputPath: refURL
                    )
                } catch {
                    throw DigaEngineError.voiceDesignFailed(
                        "Failed to generate reference audio for '\(voice.name)': \(error.localizedDescription)"
                    )
                }
            }

            FileHandle.standardError.write(
                Data("Creating voice clone from reference audio...\n".utf8)
            )

            let refData = try Data(contentsOf: refURL)
            do {
                let lock = try await VoiceLockManager.createLock(
                    characterName: voice.name,
                    candidateAudio: refData,
                    designInstruction: "",
                    modelManager: voxAltaModelManager,
                    modelRepo: resolvedBaseModelRepo
                )
                clonePromptData = lock.clonePromptData
            } catch {
                throw DigaEngineError.voiceDesignFailed(
                    "Failed to create clone prompt from reference audio: \(error.localizedDescription)"
                )
            }

        } else if let description = voice.designDescription {
            // Built-in or designed voice: generate via VoiceDesign model.
            FileHandle.standardError.write(
                Data("Generating voice '\(voice.name)' (first use, this may take a moment)...\n".utf8)
            )

            let profile = CharacterProfile(
                name: voice.name,
                gender: .unknown,
                ageRange: "",
                description: description,
                voiceTraits: [],
                summary: description
            )

            // Generate a voice candidate using VoiceDesign model.
            let candidateAudio: Data
            do {
                candidateAudio = try await VoiceDesigner.generateCandidate(
                    profile: profile,
                    modelManager: voxAltaModelManager
                )
            } catch {
                throw DigaEngineError.voiceDesignFailed(
                    "Failed to generate voice candidate for '\(voice.name)': \(error.localizedDescription)"
                )
            }

            // Extract clone prompt from the candidate audio.
            do {
                let lock = try await VoiceLockManager.createLock(
                    characterName: voice.name,
                    candidateAudio: candidateAudio,
                    designInstruction: description,
                    modelManager: voxAltaModelManager,
                    modelRepo: resolvedBaseModelRepo
                )
                clonePromptData = lock.clonePromptData
            } catch {
                throw DigaEngineError.voiceDesignFailed(
                    "Failed to extract clone prompt for '\(voice.name)': \(error.localizedDescription)"
                )
            }

            FileHandle.standardError.write(Data("Voice generated and cached.\n".utf8))

        } else {
            throw DigaEngineError.voiceDesignFailed(
                "Voice '\(voice.name)' has no design description or reference audio."
            )
        }

        // Save clone prompt to disk for future reuse.
        do {
            try FileManager.default.createDirectory(
                at: voiceStore.voicesDirectory,
                withIntermediateDirectories: true
            )
            try clonePromptData.write(to: promptFile, options: .atomic)
        } catch {
            // Non-fatal: synthesis still works, just won't be cached.
            FileHandle.standardError.write(
                Data("Warning: could not cache clone prompt to disk: \(error.localizedDescription)\n".utf8)
            )
        }

        // Update .vox file with the clone prompt if one exists.
        let voxFile = voiceStore.voicesDirectory.appendingPathComponent("\(voice.name).vox")
        if FileManager.default.fileExists(atPath: voxFile.path) {
            do {
                try VoxExporter.updateClonePrompt(in: voxFile, clonePromptData: clonePromptData)
            } catch {
                FileHandle.standardError.write(
                    Data("Warning: could not update .vox file with clone prompt: \(error.localizedDescription)\n".utf8)
                )
            }
        }

        // Cache in memory.
        cachedClonePromptData = clonePromptData
        cachedVoiceName = voice.name

        return clonePromptData
    }

    // MARK: - Sample Audio Generation

    /// Generate a sample audio clip for a voice, play it through speakers,
    /// and embed it into the voice's `.vox` file.
    ///
    /// This method:
    /// 1. Loads or creates the clone prompt for the voice
    /// 2. Synthesizes a phoneme pangram using that voice
    /// 3. Plays the generated audio through speakers
    /// 4. Writes the sample audio into the `.vox` file as an embedding
    ///
    /// - Parameter voice: The stored voice to generate a sample for.
    /// - Throws: `DigaEngineError` if synthesis or playback fails.
    func generateSampleAndUpdateVox(voice: StoredVoice) async throws {
        // 1. Load or create clone prompt.
        let clonePromptData = try await loadOrCreateClonePrompt(for: voice)

        // 2. Build a VoiceLock and synthesize the pangram.
        let voiceLock = VoiceLock(
            characterName: voice.name,
            clonePromptData: clonePromptData,
            designInstruction: voice.designDescription ?? ""
        )

        FileHandle.standardError.write(
            Data("Generating voice sample...\n".utf8)
        )

        let context = GenerationContext(phrase: VoiceDesigner.phonemePangram)
        let sampleWAV: Data
        do {
            sampleWAV = try await VoiceLockManager.generateAudio(
                context: context,
                voiceLock: voiceLock,
                language: "en",
                modelManager: voxAltaModelManager,
                modelRepo: resolvedBaseModelRepo
            )
        } catch {
            throw DigaEngineError.synthesisFailed(
                "Failed to generate voice sample: \(error.localizedDescription)"
            )
        }

        // 3. Play the sample through speakers.
        do {
            try await AudioPlayback.play(wavData: sampleWAV)
        } catch {
            FileHandle.standardError.write(
                Data("Warning: could not play sample audio: \(error.localizedDescription)\n".utf8)
            )
        }

        // 4. Write sample audio into the .vox file.
        let voxFile = voiceStore.voicesDirectory.appendingPathComponent("\(voice.name).vox")
        if FileManager.default.fileExists(atPath: voxFile.path) {
            do {
                try VoxExporter.updateSampleAudio(in: voxFile, sampleAudioData: sampleWAV)
                FileHandle.standardError.write(
                    Data("Sample audio saved to \(voice.name).vox\n".utf8)
                )
            } catch {
                FileHandle.standardError.write(
                    Data("Warning: could not update .vox with sample audio: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }
}
