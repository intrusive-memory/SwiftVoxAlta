//
//  VoxAltaErrorTests.swift
//  SwiftVoxAltaTests
//
//  Tests that all VoxAltaError cases have non-empty errorDescription.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("VoxAltaError Tests")
struct VoxAltaErrorTests {

    @Test("voiceDesignFailed has non-empty errorDescription")
    func voiceDesignFailed() {
        let error = VoxAltaError.voiceDesignFailed("generation timed out")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("generation timed out"))
    }

    @Test("cloningFailed has non-empty errorDescription")
    func cloningFailed() {
        let error = VoxAltaError.cloningFailed("reference audio too short")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("reference audio too short"))
    }

    @Test("modelNotAvailable has non-empty errorDescription")
    func modelNotAvailable() {
        let error = VoxAltaError.modelNotAvailable("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("Qwen3-TTS"))
    }

    @Test("voiceNotLoaded has non-empty errorDescription")
    func voiceNotLoaded() {
        let error = VoxAltaError.voiceNotLoaded("ELENA")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("ELENA"))
    }

    @Test("profileAnalysisFailed has non-empty errorDescription")
    func profileAnalysisFailed() {
        let error = VoxAltaError.profileAnalysisFailed("LLM returned invalid JSON")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("LLM returned invalid JSON"))
    }

    @Test("insufficientMemory has non-empty errorDescription with correct values")
    func insufficientMemory() {
        let error = VoxAltaError.insufficientMemory(available: 2_000_000_000, required: 5_000_000_000)
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("2000000000"))
        #expect(error.errorDescription!.contains("5000000000"))
    }

    @Test("audioExportFailed has non-empty errorDescription")
    func audioExportFailed() {
        let error = VoxAltaError.audioExportFailed("WAV header corrupt")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("WAV header corrupt"))
    }

    @Test("voxExportFailed has non-empty errorDescription")
    func voxExportFailed() {
        let error = VoxAltaError.voxExportFailed("archive write failed")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("archive write failed"))
    }

    @Test("voxImportFailed has non-empty errorDescription")
    func voxImportFailed() {
        let error = VoxAltaError.voxImportFailed("invalid ZIP")
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
        #expect(error.errorDescription!.contains("invalid ZIP"))
    }

    @Test("All error cases conform to Error protocol")
    func allCasesAreErrors() {
        let errors: [any Error] = [
            VoxAltaError.voiceDesignFailed("test"),
            VoxAltaError.cloningFailed("test"),
            VoxAltaError.modelNotAvailable("test"),
            VoxAltaError.voiceNotLoaded("test"),
            VoxAltaError.profileAnalysisFailed("test"),
            VoxAltaError.insufficientMemory(available: 100, required: 200),
            VoxAltaError.audioExportFailed("test"),
            VoxAltaError.voxExportFailed("test"),
            VoxAltaError.voxImportFailed("test"),
        ]

        #expect(errors.count == 9)
        for error in errors {
            #expect(error is VoxAltaError)
            let voxError = error as! VoxAltaError
            #expect(voxError.errorDescription != nil)
            #expect(!voxError.errorDescription!.isEmpty)
        }
    }
}
