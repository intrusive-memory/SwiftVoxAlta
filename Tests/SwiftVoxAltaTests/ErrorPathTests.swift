//
//  ErrorPathTests.swift
//  SwiftVoxAltaTests
//
//  Tests for error paths across the VoxAlta pipeline.
//  Verifies that appropriate errors are thrown for invalid inputs and edge cases.
//

import Foundation
import Testing
@preconcurrency import MLX
@testable import SwiftVoxAlta

// MARK: - VoiceProvider Error Paths

@Suite("Error Paths - VoiceProvider")
struct VoiceProviderErrorPathTests {

    @Test("generateAudio with unloaded voice throws voiceNotLoaded")
    func generateAudioUnloadedVoice() async {
        let provider = VoxAltaVoiceProvider()

        do {
            _ = try await provider.generateAudio(
                text: "Hello world",
                voiceId: "NONEXISTENT",
                languageCode: "en"
            )
            Issue.record("Expected voiceNotLoaded error")
        } catch let error as VoxAltaError {
            if case .voiceNotLoaded(let voiceId) = error {
                #expect(voiceId == "NONEXISTENT")
                #expect(error.errorDescription?.contains("NONEXISTENT") == true)
            } else {
                Issue.record("Expected voiceNotLoaded, got \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error))")
        }
    }

    @Test("generateAudio with empty voiceId string throws voiceNotLoaded")
    func generateAudioEmptyVoiceId() async {
        let provider = VoxAltaVoiceProvider()

        do {
            _ = try await provider.generateAudio(
                text: "Hello",
                voiceId: "",
                languageCode: "en"
            )
            Issue.record("Expected voiceNotLoaded error for empty voice ID")
        } catch let error as VoxAltaError {
            if case .voiceNotLoaded(let voiceId) = error {
                #expect(voiceId == "")
            } else {
                Issue.record("Expected voiceNotLoaded, got \(error)")
            }
        } catch {
            // Other errors also acceptable (empty ID is not in cache)
        }
    }
}

// MARK: - VoiceLockManager Error Paths

@Suite("Error Paths - VoiceLockManager")
struct VoiceLockManagerErrorPathTests {

    @Test("generateAudio with corrupted clone prompt data throws cloningFailed or modelNotAvailable")
    func generateAudioCorruptedClonePrompt() async {
        let manager = VoxAltaModelManager()
        let lock = VoiceLock(
            characterName: "TEST",
            clonePromptData: Data(),  // Empty/corrupted clone prompt
            designInstruction: "A test voice."
        )

        do {
            _ = try await VoiceLockManager.generateAudio(
                text: "Hello",
                voiceLock: lock,
                language: "en",
                modelManager: manager
            )
            Issue.record("Expected error with corrupted clone prompt data")
        } catch let error as VoxAltaError {
            // Should be modelNotAvailable, cloningFailed, or insufficientMemory
            // depending on whether memory validation or model loading fails first
            switch error {
            case .modelNotAvailable, .cloningFailed, .insufficientMemory:
                break // Expected
            default:
                Issue.record("Expected modelNotAvailable, cloningFailed, or insufficientMemory, got \(error)")
            }
        } catch {
            // Other errors from mlx-audio-swift are also acceptable
        }
    }

    @Test("createLock with invalid candidate audio throws cloningFailed or modelNotAvailable")
    func createLockInvalidCandidateAudio() async {
        let manager = VoxAltaModelManager()

        do {
            _ = try await VoiceLockManager.createLock(
                characterName: "TEST",
                candidateAudio: Data([0x00, 0x01]),  // Not valid WAV
                designInstruction: "test",
                modelManager: manager
            )
            Issue.record("Expected error with invalid candidate audio")
        } catch let error as VoxAltaError {
            switch error {
            case .modelNotAvailable, .cloningFailed, .insufficientMemory:
                break // Expected
            default:
                Issue.record("Expected modelNotAvailable, cloningFailed, or insufficientMemory, got \(error)")
            }
        } catch {
            // Other errors also acceptable
        }
    }
}

// MARK: - VoxAltaModelManager Error Paths

@Suite("Error Paths - VoxAltaModelManager")
struct ModelManagerErrorPathTests {

    @Test("validateMemory with absurdly large requirement throws insufficientMemory")
    func validateMemoryAbsurdRequirement() async {
        let manager = VoxAltaModelManager()

        // 500 GB -- no current machine has this much available memory
        let absurdSize = 500_000_000_000

        do {
            try await manager.validateMemory(forModelSizeBytes: absurdSize)
            Issue.record("Expected insufficientMemory error for 500GB requirement")
        } catch let error as VoxAltaError {
            if case .insufficientMemory(let available, let required) = error {
                #expect(available > 0, "Available memory should be positive")
                #expect(required > available, "Required should exceed available")
                // Verify headroom multiplier was applied: required = absurdSize * 1.5
                let expectedRequired = Int(Double(absurdSize) * Qwen3TTSModelSize.headroomMultiplier)
                #expect(required == expectedRequired,
                        "Required should be absurdSize * headroom multiplier")
            } else {
                Issue.record("Expected insufficientMemory, got \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error))")
        }
    }

    @Test("validateMemory with zero bytes succeeds")
    func validateMemoryZeroBytes() async throws {
        let manager = VoxAltaModelManager()
        // 0 bytes should always pass (0 * 1.5 = 0, available >= 0)
        try await manager.validateMemory(forModelSizeBytes: 0)
    }
}

// MARK: - AudioConversion Error Paths

@Suite("Error Paths - AudioConversion")
struct AudioConversionErrorPathTests {

    @Test("wavDataToMLXArray with invalid data throws audioExportFailed")
    func wavDataInvalid() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        do {
            _ = try AudioConversion.wavDataToMLXArray(invalidData)
            Issue.record("Expected audioExportFailed for invalid WAV data")
        } catch let error as VoxAltaError {
            if case .audioExportFailed(let detail) = error {
                #expect(!detail.isEmpty, "Error detail should not be empty")
            } else {
                Issue.record("Expected audioExportFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error))")
        }
    }

    @Test("wavDataToMLXArray with empty data throws audioExportFailed")
    func wavDataEmpty() {
        do {
            _ = try AudioConversion.wavDataToMLXArray(Data())
            Issue.record("Expected audioExportFailed for empty data")
        } catch let error as VoxAltaError {
            if case .audioExportFailed = error {
                // Expected
            } else {
                Issue.record("Expected audioExportFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error))")
        }
    }

    @Test("wavDataToMLXArray with RIFF header but no WAVE marker throws")
    func wavDataMissingWAVEMarker() {
        var data = Data(repeating: 0x00, count: 44)
        // Write "RIFF" header
        data[0] = 0x52; data[1] = 0x49; data[2] = 0x46; data[3] = 0x46
        // Wrong format marker (not "WAVE")
        data[8] = 0x41; data[9] = 0x42; data[10] = 0x43; data[11] = 0x44

        do {
            _ = try AudioConversion.wavDataToMLXArray(data)
            Issue.record("Expected audioExportFailed for missing WAVE marker")
        } catch is VoxAltaError {
            // Expected
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error))")
        }
    }

    @Test("mlxArrayToWAVData with empty array produces valid minimal WAV")
    func emptyArrayProducesValidWAV() throws {
        let empty = MLXArray([Float]())
        let wavData = try AudioConversion.mlxArrayToWAVData(empty)

        // Should be exactly 44 bytes (header only, zero-length data chunk)
        #expect(wavData.count == 44, "Empty audio WAV should be 44 bytes (header only)")

        // Verify it has RIFF/WAVE markers
        let riff = String(data: wavData[0..<4], encoding: .ascii)
        let wave = String(data: wavData[8..<12], encoding: .ascii)
        #expect(riff == "RIFF")
        #expect(wave == "WAVE")

        // Verify data chunk size is 0
        let dataSize = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataSize == 0, "Empty WAV data chunk size should be 0")
    }
}
