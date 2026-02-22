//
//  TypeTests.swift
//  SwiftVoxAltaTests
//
//  Tests Codable round-trips for VoiceLock and VoxAltaConfig.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("Type Codable Round-Trip Tests")
struct TypeTests {

    // MARK: - VoiceLock

    @Test("VoiceLock round-trips through JSON encoding and decoding")
    func voiceLockCodable() throws {
        let cloneData = Data([0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD])
        let lockedDate = Date(timeIntervalSince1970: 1700000000)

        let voiceLock = VoiceLock(
            characterName: "ELENA",
            clonePromptData: cloneData,
            designInstruction: "A warm female voice in her 30s with a slightly husky quality.",
            lockedAt: lockedDate
        )

        let data = try JSONEncoder().encode(voiceLock)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: data)

        #expect(decoded.characterName == voiceLock.characterName)
        #expect(decoded.clonePromptData == voiceLock.clonePromptData)
        #expect(decoded.designInstruction == voiceLock.designInstruction)
        #expect(decoded.lockedAt == voiceLock.lockedAt)
    }

    // MARK: - VoxAltaConfig

    @Test("VoxAltaConfig round-trips through JSON encoding and decoding")
    func voxAltaConfigCodable() throws {
        let config = VoxAltaConfig(
            designModel: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
            renderModel: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
            analysisModel: "mlx-community/Qwen3-4B-4bit",
            candidateCount: 5,
            outputFormat: .m4a
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VoxAltaConfig.self, from: data)

        #expect(decoded.designModel == config.designModel)
        #expect(decoded.renderModel == config.renderModel)
        #expect(decoded.analysisModel == config.analysisModel)
        #expect(decoded.candidateCount == config.candidateCount)
        #expect(decoded.outputFormat == config.outputFormat)
    }

    @Test("VoxAltaConfig default has sensible values")
    func voxAltaConfigDefault() {
        let config = VoxAltaConfig.default

        #expect(!config.designModel.isEmpty)
        #expect(!config.renderModel.isEmpty)
        #expect(!config.analysisModel.isEmpty)
        #expect(config.candidateCount > 0)
        #expect(config.outputFormat == .wav)
    }

    @Test("All AudioOutputFormat cases round-trip through Codable")
    func audioOutputFormatCodable() throws {
        for format in [AudioOutputFormat.wav, .aiff, .m4a] {
            let data = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(AudioOutputFormat.self, from: data)
            #expect(decoded == format)
        }
    }
}
