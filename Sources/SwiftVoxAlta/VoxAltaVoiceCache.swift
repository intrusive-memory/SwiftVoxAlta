//
//  VoxAltaVoiceCache.swift
//  SwiftVoxAlta
//
//  Thread-safe actor-based cache for loaded voice clone prompts.
//

import Foundation

/// Thread-safe cache for voice clone prompt data, keyed by voice ID (character name).
///
/// `VoxAltaVoiceCache` is an actor that stores deserialized clone prompt data
/// along with optional metadata (gender) for each loaded voice. The cache is
/// used by `VoxAltaVoiceProvider` to look up clone prompts when generating audio.
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

    // MARK: - Public API

    /// Store a voice in the cache.
    ///
    /// - Parameters:
    ///   - id: The voice identifier (typically the character name, e.g., "ELENA").
    ///   - data: The serialized clone prompt data.
    ///   - gender: Optional gender descriptor for the voice.
    public func store(id: String, data: Data, gender: String?) {
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
    }

    /// Retrieve a cached voice by ID.
    ///
    /// - Parameter id: The voice identifier to look up.
    /// - Returns: The cached voice entry, or `nil` if not found.
    public func get(id: String) -> CachedVoice? {
        voices[id]
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
}
