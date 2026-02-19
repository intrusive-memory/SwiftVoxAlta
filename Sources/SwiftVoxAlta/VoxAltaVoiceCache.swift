//
//  VoxAltaVoiceCache.swift
//  SwiftVoxAlta
//
//  Thread-safe actor-based cache for loaded voice clone prompts.
//

import Foundation
@preconcurrency import MLXAudioTTS

/// Thread-safe cache for voice clone prompt data, keyed by voice ID (character name).
///
/// `VoxAltaVoiceCache` is an actor that stores deserialized clone prompt data
/// along with optional metadata (gender) for each loaded voice. The cache is
/// used by `VoxAltaVoiceProvider` to look up clone prompts when generating audio.
///
/// In addition to storing serialized clone prompt data, this cache maintains
/// deserialized `VoiceClonePrompt` instances to avoid repeated deserialization
/// overhead during audio generation.
public actor VoxAltaVoiceCache {

    /// A cached voice entry containing clone prompt data and optional metadata.
    public struct CachedVoice: Sendable {
        /// The serialized clone prompt data for voice cloning.
        public let clonePromptData: Data

        /// Optional gender descriptor (e.g., "male", "female", "non-binary").
        public let gender: String?

        public init(clonePromptData: Data, gender: String?) {
            self.clonePromptData = clonePromptData
            self.gender = gender
        }
    }

    // MARK: - State

    private var voices: [String: CachedVoice] = [:]

    /// Cache of deserialized clone prompts to avoid repeated deserialization.
    /// Keyed by voice ID (character name). Cleared on unloadAllVoices().
    private var clonePromptCache: [String: VoiceClonePrompt] = [:]

    // MARK: - Public API

    /// Store a voice in the cache.
    ///
    /// - Parameters:
    ///   - id: The voice identifier (typically the character name, e.g., "ELENA").
    ///   - data: The serialized clone prompt data.
    ///   - gender: Optional gender descriptor for the voice.
    public func store(id: String, data: Data, gender: String?) {
        let dataHash = data.prefix(16).map { String(format: "%02x", $0) }.joined()
        FileHandle.standardError.write(Data("[VoxAltaVoiceCache] 📥 Storing voice '\(id)' (data hash: \(dataHash), size: \(data.count) bytes)\n".utf8))
        voices[id] = CachedVoice(clonePromptData: data, gender: gender)
    }

    /// Remove a voice from the cache.
    ///
    /// - Parameter id: The voice identifier to remove.
    public func remove(id: String) {
        voices[id] = nil
    }

    /// Remove all voices from the cache.
    public func removeAll() {
        voices.removeAll()
        clonePromptCache.removeAll()
    }

    /// Retrieve a cached voice by ID.
    ///
    /// - Parameter id: The voice identifier to look up.
    /// - Returns: The cached voice entry, or `nil` if not found.
    public func get(id: String) -> CachedVoice? {
        let result = voices[id]
        if result != nil {
            let dataHash = result!.clonePromptData.prefix(16).map { String(format: "%02x", $0) }.joined()
            FileHandle.standardError.write(Data("[VoxAltaVoiceCache] 🔍 Retrieved voice '\(id)' (data hash: \(dataHash))\n".utf8))
        } else {
            let cachedIds = voices.keys.sorted().joined(separator: ", ")
            FileHandle.standardError.write(Data("[VoxAltaVoiceCache] ❌ Voice '\(id)' NOT FOUND in cache. Available: [\(cachedIds)]\n".utf8))
        }
        return result
    }

    /// Return all voice IDs currently in the cache.
    ///
    /// - Returns: An array of voice identifier strings.
    public func allVoiceIds() -> [String] {
        Array(voices.keys)
    }

    /// Return all cached voices as an array of (id, voice) tuples.
    ///
    /// - Returns: An array of tuples containing the voice ID and cached voice entry.
    public func allVoices() -> [(id: String, voice: CachedVoice)] {
        voices.map { (id: $0.key, voice: $0.value) }
    }

    /// The number of voices currently in the cache.
    public var count: Int {
        voices.count
    }

    // MARK: - Clone Prompt Cache

    /// Retrieve a deserialized clone prompt from the cache.
    ///
    /// - Parameter id: The voice identifier to look up.
    /// - Returns: The cached `VoiceClonePrompt`, or `nil` if not found.
    public func getClonePrompt(id: String) -> VoiceClonePrompt? {
        clonePromptCache[id]
    }

    /// Store a deserialized clone prompt in the cache.
    ///
    /// - Parameters:
    ///   - id: The voice identifier (character name).
    ///   - clonePrompt: The deserialized `VoiceClonePrompt` to cache.
    public func storeClonePrompt(id: String, clonePrompt: VoiceClonePrompt) {
        clonePromptCache[id] = clonePrompt
    }
}
