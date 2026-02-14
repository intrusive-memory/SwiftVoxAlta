//
//  VoxAltaVoiceProvider.swift
//  SwiftVoxAlta
//
//  VoiceProvider conformance for on-device Qwen3-TTS voice generation via VoxAlta.
//

import Foundation
import SwiftHablare
@preconcurrency import MLXAudioTTS
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
#if canImport(SwiftUI)
import SwiftUI
#endif

/// On-device VoiceProvider implementation using Qwen3-TTS models via mlx-audio-swift.
///
/// `VoxAltaVoiceProvider` manages a cache of loaded voices (clone prompts) and generates
/// speech audio using the locked voice identity. Voices must be loaded via `loadVoice(id:clonePromptData:)`
/// before calling `generateAudio`. The voice ID is typically the character name (e.g., "ELENA").
///
/// This class conforms to `VoiceProvider` from SwiftHablare and is marked `@unchecked Sendable`
/// because all mutable state is held in the `VoxAltaVoiceCache` actor and the `VoxAltaModelManager`
/// actor, both of which are inherently thread-safe.
public final class VoxAltaVoiceProvider: VoiceProvider, @unchecked Sendable {

    // MARK: - VoiceProvider Metadata

    public let providerId = "voxalta"
    public let displayName = "VoxAlta (On-Device)"
    public let requiresAPIKey = false
    public let mimeType = "audio/wav"
    public var defaultVoiceId: String? { nil }

    // MARK: - Preset Speakers

    /// CustomVoice preset speakers available without clone prompts.
    private static let presetSpeakers: [(id: String, name: String, description: String, gender: String, mlxSpeaker: String)] = [
        ("ryan", "Ryan", "Dynamic male voice with strong rhythmic drive", "male", "ryan"),
        ("aiden", "Aiden", "Sunny American male voice with clear midrange", "male", "aiden"),
        ("vivian", "Vivian", "Bright, slightly edgy young Chinese female voice", "female", "vivian"),
        ("serena", "Serena", "Warm, gentle young Chinese female voice", "female", "serena"),
        ("uncle_fu", "Uncle Fu", "Seasoned Chinese male voice with low, mellow timbre", "male", "uncle_fu"),
        ("dylan", "Dylan", "Youthful Beijing male voice with clear timbre", "male", "dylan"),
        ("eric", "Eric", "Lively Chengdu male voice with husky brightness", "male", "eric"),
        ("anna", "Anna", "Playful Japanese female voice with light timbre", "female", "ono_anna"),
        ("sohee", "Sohee", "Warm Korean female voice with rich emotion", "female", "sohee"),
    ]

    // MARK: - Internal State

    /// The model manager used for loading/unloading Qwen3-TTS models.
    private let modelManager: VoxAltaModelManager

    /// Thread-safe cache of loaded voice clone prompts.
    private let voiceCache: VoxAltaVoiceCache

    // MARK: - Initialization

    /// Create a new VoxAlta voice provider.
    ///
    /// - Parameter modelManager: The model manager to use for TTS model operations.
    ///   Defaults to a new instance.
    public init(modelManager: VoxAltaModelManager = VoxAltaModelManager()) {
        self.modelManager = modelManager
        self.voiceCache = VoxAltaVoiceCache()
    }

    // MARK: - VoiceProvider Protocol

    /// Check if the provider is configured.
    ///
    /// Returns `true` because VoxAlta models are downloaded on demand.
    /// No API key or pre-configuration is required.
    public func isConfigured() async -> Bool {
        true
    }

    /// Fetch currently loaded voices.
    ///
    /// Returns preset speakers and voices that have been loaded via `loadVoice(id:clonePromptData:)`.
    /// Unlike cloud-based providers, VoxAlta does not fetch from a remote catalog.
    ///
    /// - Parameter languageCode: The language code to associate with returned voices.
    /// - Returns: An array of `Voice` objects representing preset speakers and loaded voices.
    public func fetchVoices(languageCode: String) async throws -> [Voice] {
        // Start with preset speakers
        var voices = Self.presetSpeakers.map { speaker in
            Voice(
                id: speaker.id,
                name: speaker.name,
                description: speaker.description,
                providerId: providerId,
                language: languageCode,
                gender: speaker.gender
            )
        }

        // Append cached custom voices
        let cached = await voiceCache.allVoices()
        voices.append(contentsOf: cached.map { entry in
            Voice(
                id: entry.id,
                name: entry.id,
                description: "VoxAlta on-device voice",
                providerId: providerId,
                language: languageCode,
                gender: entry.voice.gender
            )
        })

        return voices
    }

    /// Generate speech audio from text using a loaded voice.
    ///
    /// The voice must have been previously loaded via `loadVoice(id:clonePromptData:)`.
    /// Audio is generated using the Base model with the stored clone prompt for
    /// consistent voice identity.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceId: The voice identifier (character name) to use.
    ///   - languageCode: The language code for generation (e.g., "en").
    /// - Returns: WAV format audio data (24kHz, 16-bit PCM, mono).
    /// - Throws: `VoxAltaError.voiceNotLoaded` if the voice is not in the cache,
    ///           or other errors from model loading and audio generation.
    public func generateAudio(text: String, voiceId: String, languageCode: String) async throws -> Data {
        // Route 1: CustomVoice preset speaker (fast path)
        if let speaker = presetSpeaker(for: voiceId) {
            return try await generateWithPresetSpeaker(
                text: text,
                speakerName: speaker.mlxSpeaker,
                language: languageCode
            )
        }

        // Route 2: Clone prompt (custom voice)
        guard let cached = await voiceCache.get(id: voiceId) else {
            throw VoxAltaError.voiceNotLoaded(voiceId)
        }

        // Build a VoiceLock from the cached clone prompt data
        let voiceLock = VoiceLock(
            characterName: voiceId,
            clonePromptData: cached.clonePromptData,
            designInstruction: ""  // Not needed for generation
        )

        return try await VoiceLockManager.generateAudio(
            text: text,
            voiceLock: voiceLock,
            language: languageCode,
            modelManager: modelManager
        )
    }

    /// Generate processed audio with duration measurement.
    ///
    /// Generates audio via `generateAudio`, then computes the duration from the WAV data.
    /// The returned `ProcessedAudio` uses `"audio/wav"` as the MIME type since VoxAlta
    /// outputs WAV directly without transcoding.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceId: The voice identifier (character name) to use.
    ///   - languageCode: The language code for generation.
    /// - Returns: A `ProcessedAudio` containing the WAV data and measured duration.
    public func generateProcessedAudio(
        text: String,
        voiceId: String,
        languageCode: String
    ) async throws -> ProcessedAudio {
        let audioData = try await generateAudio(text: text, voiceId: voiceId, languageCode: languageCode)
        let duration = Self.measureWAVDuration(audioData)

        return ProcessedAudio(
            audioData: audioData,
            durationSeconds: duration,
            trimmedStart: 0,
            trimmedEnd: 0,
            mimeType: mimeType
        )
    }

    /// Estimate the duration of audio that would be generated from the given text.
    ///
    /// Uses a simple heuristic: word count divided by 150 words per minute.
    ///
    /// - Parameters:
    ///   - text: The text to estimate duration for.
    ///   - voiceId: The voice identifier (unused for estimation).
    /// - Returns: Estimated duration in seconds.
    public func estimateDuration(text: String, voiceId: String) async -> TimeInterval {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let wordsPerMinute: Double = 150.0
        return Double(wordCount) / wordsPerMinute * 60.0
    }

    /// Check if a specific voice is available (loaded) in the cache.
    ///
    /// - Parameter voiceId: The voice identifier to check.
    /// - Returns: `true` if the voice is a preset speaker or has been loaded, `false` otherwise.
    public func isVoiceAvailable(voiceId: String) async -> Bool {
        // Preset speakers are always available
        if isPresetSpeaker(voiceId) {
            return true
        }

        // Check cache for custom voices
        let cached = await voiceCache.get(id: voiceId)
        return cached != nil
    }

    #if canImport(SwiftUI)
    /// Build the SwiftUI configuration panel for VoxAlta.
    ///
    /// Returns a minimal placeholder view. Configuration is handled externally
    /// by the application (Produciesta) through the voice design workflow.
    @MainActor
    public func makeConfigurationView(onConfigured: @escaping (Bool) -> Void) -> AnyView {
        AnyView(
            VStack(spacing: 12) {
                Text("VoxAlta (On-Device)")
                    .font(.headline)
                Text("On-device voice generation using Qwen3-TTS. No API key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    onConfigured(true)
                }
            }
            .padding()
        )
    }
    #endif

    // MARK: - VoxAlta-Specific API

    /// Load a voice into the cache for use with `generateAudio`.
    ///
    /// This must be called before attempting to generate audio for a given voice ID.
    /// The clone prompt data is typically obtained from a `VoiceLock` created during
    /// the voice design workflow.
    ///
    /// - Parameters:
    ///   - id: The voice identifier (typically a character name, e.g., "ELENA").
    ///   - clonePromptData: The serialized clone prompt data from a `VoiceLock`.
    ///   - gender: Optional gender descriptor for the voice.
    public func loadVoice(id: String, clonePromptData: Data, gender: String? = nil) async {
        await voiceCache.store(id: id, data: clonePromptData, gender: gender)
    }

    /// Unload a voice from the cache.
    ///
    /// - Parameter id: The voice identifier to remove.
    public func unloadVoice(id: String) async {
        await voiceCache.remove(id: id)
    }

    /// Unload all voices from the cache.
    public func unloadAllVoices() async {
        await voiceCache.removeAll()
    }

    // MARK: - Private Helpers (Preset Speakers)

    /// Check if a voice ID corresponds to a preset speaker.
    ///
    /// - Parameter voiceId: The voice identifier to check.
    /// - Returns: `true` if the voice ID matches a preset speaker, `false` otherwise.
    private func isPresetSpeaker(_ voiceId: String) -> Bool {
        Self.presetSpeakers.contains { $0.id == voiceId }
    }

    /// Get preset speaker details by ID.
    private func presetSpeaker(for voiceId: String) -> (id: String, name: String, description: String, gender: String, mlxSpeaker: String)? {
        Self.presetSpeakers.first { $0.id == voiceId }
    }

    /// Generate audio using a CustomVoice preset speaker.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - speakerName: The preset speaker ID (e.g., "ryan").
    ///   - language: The language code for generation.
    /// - Returns: WAV format audio data (24kHz, 16-bit PCM, mono).
    private func generateWithPresetSpeaker(
        text: String,
        speakerName: String,
        language: String
    ) async throws -> Data {
        let model = try await modelManager.loadModel(.customVoice1_7B)

        guard let qwenModel = model as? Qwen3TTSModel else {
            throw VoxAltaError.modelNotAvailable(
                "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
            )
        }

        let audioArray = try await qwenModel.generate(
            text: text,
            voice: speakerName,
            refAudio: nil,
            refText: nil,
            language: language,
            generationParameters: GenerateParameters()
        )

        return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
    }

    // MARK: - Private Helpers

    /// Measure the duration of WAV audio data by parsing the header.
    ///
    /// Computes duration as: `dataChunkSize / (sampleRate * numChannels * bytesPerSample)`.
    /// Returns 0 if the WAV data cannot be parsed.
    ///
    /// - Parameter data: WAV format audio data.
    /// - Returns: Duration in seconds, or 0 if the data cannot be parsed.
    static func measureWAVDuration(_ data: Data) -> Double {
        // Minimum WAV header is 44 bytes
        guard data.count >= 44 else { return 0 }

        // Validate RIFF/WAVE markers
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return 0
        }

        // Parse chunks to find fmt and data
        var offset = 12
        var sampleRate: UInt32 = 0
        var numChannels: UInt16 = 0
        var bitsPerSample: UInt16 = 0
        var dataSize: UInt32 = 0

        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize = data.withUnsafeBytes { buffer in
                buffer.load(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
            }

            if chunkID == "fmt " && chunkSize >= 16 {
                data.withUnsafeBytes { buffer in
                    numChannels = buffer.load(fromByteOffset: offset + 10, as: UInt16.self).littleEndian
                    sampleRate = buffer.load(fromByteOffset: offset + 12, as: UInt32.self).littleEndian
                    bitsPerSample = buffer.load(fromByteOffset: offset + 22, as: UInt16.self).littleEndian
                }
            } else if chunkID == "data" {
                dataSize = chunkSize
            }

            offset += 8 + Int(chunkSize)
            if offset % 2 != 0 { offset += 1 }
        }

        guard sampleRate > 0, numChannels > 0, bitsPerSample > 0 else { return 0 }

        let bytesPerSample = Double(bitsPerSample) / 8.0
        let bytesPerSecond = Double(sampleRate) * Double(numChannels) * bytesPerSample
        return Double(dataSize) / bytesPerSecond
    }
}
