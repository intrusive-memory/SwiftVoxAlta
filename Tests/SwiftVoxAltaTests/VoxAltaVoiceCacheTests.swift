//
//  VoxAltaVoiceCacheTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoxAltaVoiceCache actor.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("VoxAltaVoiceCache - Storage Operations")
struct VoxAltaVoiceCacheStorageTests {

    @Test("Store and retrieve a voice")
    func storeAndRetrieve() async {
        let cache = VoxAltaVoiceCache()
        let data = Data([0x01, 0x02, 0x03])

        await cache.store(id: "ELENA", data: data, gender: "female")

        let retrieved = await cache.get(id: "ELENA")
        #expect(retrieved != nil)
        #expect(retrieved?.clonePromptData == data)
        #expect(retrieved?.gender == "female")
    }

    @Test("Retrieve returns nil for unknown voice")
    func retrieveUnknown() async {
        let cache = VoxAltaVoiceCache()

        let result = await cache.get(id: "NOBODY")
        #expect(result == nil)
    }

    @Test("Store overwrites existing voice")
    func storeOverwrites() async {
        let cache = VoxAltaVoiceCache()
        let data1 = Data([0x01])
        let data2 = Data([0x02])

        await cache.store(id: "ELENA", data: data1, gender: "female")
        await cache.store(id: "ELENA", data: data2, gender: "male")

        let retrieved = await cache.get(id: "ELENA")
        #expect(retrieved?.clonePromptData == data2)
        #expect(retrieved?.gender == "male")
    }

    @Test("Store with nil gender")
    func storeNilGender() async {
        let cache = VoxAltaVoiceCache()

        await cache.store(id: "GHOST", data: Data([0xFF]), gender: nil)

        let retrieved = await cache.get(id: "GHOST")
        #expect(retrieved != nil)
        #expect(retrieved?.gender == nil)
    }
}

@Suite("VoxAltaVoiceCache - Remove Operations")
struct VoxAltaVoiceCacheRemoveTests {

    @Test("Remove a stored voice")
    func removeVoice() async {
        let cache = VoxAltaVoiceCache()

        await cache.store(id: "ELENA", data: Data([0x01]), gender: "female")
        await cache.remove(id: "ELENA")

        let result = await cache.get(id: "ELENA")
        #expect(result == nil)
    }

    @Test("Remove non-existent voice is a no-op")
    func removeNonExistent() async {
        let cache = VoxAltaVoiceCache()

        // Should not crash
        await cache.remove(id: "NOBODY")

        let count = await cache.count
        #expect(count == 0)
    }

    @Test("Remove all voices clears the cache")
    func removeAll() async {
        let cache = VoxAltaVoiceCache()

        await cache.store(id: "ELENA", data: Data([0x01]), gender: "female")
        await cache.store(id: "MARCUS", data: Data([0x02]), gender: "male")
        await cache.store(id: "GHOST", data: Data([0x03]), gender: nil)

        let countBefore = await cache.count
        #expect(countBefore == 3)

        await cache.removeAll()

        let countAfter = await cache.count
        #expect(countAfter == 0)
    }
}

@Suite("VoxAltaVoiceCache - Query Operations")
struct VoxAltaVoiceCacheQueryTests {

    @Test("allVoiceIds returns all stored IDs")
    func allVoiceIds() async {
        let cache = VoxAltaVoiceCache()

        await cache.store(id: "ELENA", data: Data([0x01]), gender: "female")
        await cache.store(id: "MARCUS", data: Data([0x02]), gender: "male")

        let ids = await cache.allVoiceIds()
        #expect(ids.count == 2)
        #expect(ids.contains("ELENA"))
        #expect(ids.contains("MARCUS"))
    }

    @Test("allVoiceIds is empty for empty cache")
    func allVoiceIdsEmpty() async {
        let cache = VoxAltaVoiceCache()

        let ids = await cache.allVoiceIds()
        #expect(ids.isEmpty)
    }

    @Test("allVoices returns all entries")
    func allVoices() async {
        let cache = VoxAltaVoiceCache()
        let data1 = Data([0x01])
        let data2 = Data([0x02])

        await cache.store(id: "ELENA", data: data1, gender: "female")
        await cache.store(id: "MARCUS", data: data2, gender: "male")

        let voices = await cache.allVoices()
        #expect(voices.count == 2)

        let elenaEntry = voices.first(where: { $0.id == "ELENA" })
        #expect(elenaEntry != nil)
        #expect(elenaEntry?.voice.clonePromptData == data1)
        #expect(elenaEntry?.voice.gender == "female")

        let marcusEntry = voices.first(where: { $0.id == "MARCUS" })
        #expect(marcusEntry != nil)
        #expect(marcusEntry?.voice.clonePromptData == data2)
        #expect(marcusEntry?.voice.gender == "male")
    }

    @Test("Count reflects stored voice count")
    func count() async {
        let cache = VoxAltaVoiceCache()

        let count0 = await cache.count
        #expect(count0 == 0)

        await cache.store(id: "ELENA", data: Data([0x01]), gender: nil)
        let count1 = await cache.count
        #expect(count1 == 1)

        await cache.store(id: "MARCUS", data: Data([0x02]), gender: nil)
        let count2 = await cache.count
        #expect(count2 == 2)

        await cache.remove(id: "ELENA")
        let count3 = await cache.count
        #expect(count3 == 1)
    }
}

@Suite("VoxAltaVoiceCache - CachedVoice")
struct VoxAltaVoiceCacheCachedVoiceTests {

    @Test("CachedVoice initializer stores values")
    func cachedVoiceInit() {
        let data = Data([0xAA, 0xBB])
        let voice = VoxAltaVoiceCache.CachedVoice(clonePromptData: data, gender: "female")

        #expect(voice.clonePromptData == data)
        #expect(voice.gender == "female")
    }

    @Test("CachedVoice is Sendable")
    func cachedVoiceIsSendable() {
        let voice: any Sendable = VoxAltaVoiceCache.CachedVoice(
            clonePromptData: Data([0x01]),
            gender: nil
        )
        #expect(voice is VoxAltaVoiceCache.CachedVoice)
    }
}
