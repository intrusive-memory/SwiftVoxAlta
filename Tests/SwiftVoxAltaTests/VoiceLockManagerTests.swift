//
//  VoiceLockManagerTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoiceLockManager API existence and VoiceLock serialization.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("VoiceLockManager - API Existence")
struct VoiceLockManagerAPITests {

    @Test("VoiceLockManager is an enum namespace")
    func isEnumNamespace() {
        // VoiceLockManager is an enum with no cases — this is a compile test.
        // If it were a struct or class, this test structure would be different.
        // The fact that this file compiles proves the type exists as expected.
        let _: VoiceLockManager.Type = VoiceLockManager.self
    }

    @Test("VoiceLockManager.createLock signature exists")
    func createLockSignatureExists() async {
        // This test verifies the createLock method signature compiles.
        // We cannot call it without a real model, but we verify the types.
        let manager = VoxAltaModelManager()
        let candidateData = Data([0x00])

        // Verify the method exists and has the expected parameter types.
        // We expect this to throw (no model available), which is fine — we're
        // testing that the API compiles.
        do {
            _ = try await VoiceLockManager.createLock(
                characterName: "TEST",
                candidateAudio: candidateData,
                designInstruction: "A test voice.",
                modelManager: manager
            )
            Issue.record("Expected createLock to throw without a loaded model")
        } catch {
            // Expected: model not available or similar error
            #expect(error is VoxAltaError)
        }
    }

    @Test("VoiceLockManager.generateAudio signature exists")
    func generateAudioSignatureExists() async {
        // Compile test for generateAudio method signature.
        let manager = VoxAltaModelManager()
        let lock = VoiceLock(
            characterName: "TEST",
            clonePromptData: Data([0x00]),
            designInstruction: "A test voice."
        )

        do {
            _ = try await VoiceLockManager.generateAudio(
                text: "Hello",
                voiceLock: lock,
                language: "en",
                modelManager: manager
            )
            Issue.record("Expected generateAudio to throw without a loaded model")
        } catch {
            // Expected: model not available or similar error
            #expect(error is VoxAltaError)
        }
    }
}

@Suite("VoiceLockManager - VoiceLock Codable")
struct VoiceLockCodableTests {

    @Test("VoiceLock round-trips through JSON with real-sized clone data")
    func voiceLockCodableWithLargerData() throws {
        // Simulate a realistic clone prompt data size (several KB)
        let cloneData = Data((0..<4096).map { UInt8($0 % 256) })
        let now = Date()

        let lock = VoiceLock(
            characterName: "ELENA",
            clonePromptData: cloneData,
            designInstruction: "A warm female voice in her 30s.",
            lockedAt: now
        )

        let encoded = try JSONEncoder().encode(lock)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == "ELENA")
        #expect(decoded.clonePromptData == cloneData)
        #expect(decoded.designInstruction == "A warm female voice in her 30s.")
        #expect(decoded.lockedAt == now)
    }

    @Test("VoiceLock preserves empty clone prompt data")
    func voiceLockEmptyCloneData() throws {
        let lock = VoiceLock(
            characterName: "GHOST",
            clonePromptData: Data(),
            designInstruction: ""
        )

        let encoded = try JSONEncoder().encode(lock)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == "GHOST")
        #expect(decoded.clonePromptData.isEmpty)
        #expect(decoded.designInstruction.isEmpty)
    }

    @Test("VoiceLock preserves design instruction with special characters")
    func voiceLockSpecialCharacters() throws {
        let instruction = "A voice with \"quotes\", newlines\n, and emoji 🎤."
        let lock = VoiceLock(
            characterName: "TEST",
            clonePromptData: Data([0xFF]),
            designInstruction: instruction
        )

        let encoded = try JSONEncoder().encode(lock)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.designInstruction == instruction)
    }

    @Test("VoiceLock default lockedAt is approximately now")
    func voiceLockDefaultDate() {
        let before = Date()
        let lock = VoiceLock(
            characterName: "TEST",
            clonePromptData: Data(),
            designInstruction: "test"
        )
        let after = Date()

        #expect(lock.lockedAt >= before)
        #expect(lock.lockedAt <= after)
    }
}

@Suite("VoiceLockManager - Sendable Conformance")
struct VoiceLockManagerSendableTests {

    @Test("VoiceLock is Sendable")
    func voiceLockIsSendable() {
        let lock: any Sendable = VoiceLock(
            characterName: "TEST",
            clonePromptData: Data([0x01]),
            designInstruction: "test"
        )
        #expect(lock is VoiceLock)
    }

    @Test("VoiceLockManager type is accessible as Sendable")
    func voiceLockManagerIsSendable() {
        // VoiceLockManager is an enum namespace — enums without cases
        // are inherently Sendable. This is a compile-time verification.
        let _: any Sendable.Type = VoiceLockManager.self
    }
}
