//
//  VoiceLockManagerTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoiceLock serialization correctness.
//

import Foundation
import Testing

@testable import SwiftVoxAlta

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
