//
//  VoiceDesignIntegrationTests.swift
//  SwiftVoxAltaTests
//
//  Integration test for the complete VoiceDesign pipeline:
//  CharacterProfile → voice description → voice candidates → VoiceLock → audio generation
//
//  This test exercises all 5 pipeline steps and validates WAV format output.
//  Disabled on CI due to Metal compiler limitations.
//

import Foundation
import Testing
import SwiftCompartido
@preconcurrency import MLX
@testable import SwiftVoxAlta

@Suite(
    "Integration - VoiceDesign Pipeline",
    .disabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "Metal compiler not supported on GitHub Actions")
)
struct VoiceDesignIntegrationTests {

    // MARK: - Full VoiceDesign Pipeline Test

    @Test("Full VoiceDesign pipeline: profile → description → candidate → lock → audio")
    func fullVoiceDesignPipeline() async throws {
        // Step 1: Create CharacterProfile (from character analysis)
        let elenaProfile = CharacterProfile(
            name: "ELENA",
            gender: .female,
            ageRange: "30s",
            description: "A determined investigative journalist.",
            voiceTraits: ["warm", "confident", "slightly husky"],
            summary: "A female journalist in her 30s with a warm, confident voice."
        )

        // Step 2: Compose voice description from profile
        let voiceDescription = VoiceDesigner.composeVoiceDescription(from: elenaProfile)

        // Verify description contains expected elements
        #expect(voiceDescription.contains("female"), "Description should mention gender")
        #expect(voiceDescription.contains("30s"), "Description should mention age range")
        #expect(voiceDescription.contains("warm"), "Description should include voice traits")
        #expect(voiceDescription.contains("confident"), "Description should include voice traits")
        #expect(voiceDescription.contains("Voice traits:"), "Description should have traits section")

        // Step 3: Generate 1 voice candidate (not 3, to keep test fast)
        let modelManager = VoxAltaModelManager()
        let candidate = try await VoiceDesigner.generateCandidate(
            profile: elenaProfile,
            modelManager: modelManager
        )

        // Verify candidate is non-empty WAV data
        #expect(candidate.count > 0, "Candidate audio should not be empty")
        #expect(candidate.count > 100, "Candidate audio should be substantial (>100 bytes)")

        // Validate WAV format (RIFF header)
        let riffHeader = candidate.prefix(4)
        let riffString = String(data: riffHeader, encoding: .ascii)
        #expect(riffString == "RIFF", "Audio should have RIFF header")

        // Validate WAVE format
        let waveHeader = candidate.dropFirst(8).prefix(4)
        let waveString = String(data: waveHeader, encoding: .ascii)
        #expect(waveString == "WAVE", "Audio should be WAVE format")

        // Step 4: Create VoiceLock from candidate
        let voiceLock = try await VoiceLockManager.createLock(
            characterName: elenaProfile.name,
            candidateAudio: candidate,
            designInstruction: voiceDescription,
            modelManager: modelManager
        )

        // Verify VoiceLock metadata
        #expect(voiceLock.characterName == "ELENA", "VoiceLock should store character name")
        #expect(voiceLock.designInstruction == voiceDescription, "VoiceLock should store design instruction")
        #expect(voiceLock.clonePromptData.count > 0, "VoiceLock should contain serialized clone prompt")
        #expect(voiceLock.clonePromptData.count > 1000, "Clone prompt should be substantial (>1KB)")

        // Step 5: Generate audio from locked voice
        let dialogueText = "Did you get the documents?"
        let audioData = try await VoiceLockManager.generateAudio(
            text: dialogueText,
            voiceLock: voiceLock,
            language: "en",
            modelManager: modelManager
        )

        // Verify generated audio is non-empty WAV
        #expect(audioData.count > 0, "Generated audio should not be empty")
        #expect(audioData.count > 100, "Generated audio should be substantial")

        // Validate WAV format for generated audio
        let audioRiffHeader = audioData.prefix(4)
        let audioRiffString = String(data: audioRiffHeader, encoding: .ascii)
        #expect(audioRiffString == "RIFF", "Generated audio should have RIFF header")

        let audioWaveHeader = audioData.dropFirst(8).prefix(4)
        let audioWaveString = String(data: audioWaveHeader, encoding: .ascii)
        #expect(audioWaveString == "WAVE", "Generated audio should be WAVE format")

        // Verify WAV sample rate (24kHz = 0x5DC0 in little-endian)
        // Sample rate is at offset 24 (4 bytes, little-endian)
        if audioData.count >= 28 {
            let sampleRateBytes = audioData.dropFirst(24).prefix(4)
            let sampleRate = sampleRateBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
            #expect(sampleRate == 24000, "WAV sample rate should be 24kHz (24000 Hz)")
        } else {
            Issue.record("WAV data too short to verify sample rate")
        }

        // Verify WAV is mono (1 channel at offset 22)
        if audioData.count >= 24 {
            let channelBytes = audioData.dropFirst(22).prefix(2)
            let channels = channelBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
            #expect(channels == 1, "WAV should be mono (1 channel)")
        } else {
            Issue.record("WAV data too short to verify channel count")
        }
    }

    // MARK: - Parallel Multi-Candidate Generation Test

    @Test("Parallel generation produces correct count and valid WAV candidates")
    func parallelMultiCandidateGeneration() async throws {
        // This test exercises the parallel TaskGroup-based generateCandidates() path.
        // VoiceDesigner.generateCandidates() uses withThrowingTaskGroup internally.
        let profile = CharacterProfile(
            name: "TEST_CHARACTER",
            gender: .male,
            ageRange: "40s",
            description: "A test character for parallel multi-candidate generation.",
            voiceTraits: ["deep", "authoritative"],
            summary: "A male test character in his 40s."
        )

        let modelManager = VoxAltaModelManager()

        // Measure wall-clock time for parallel generation
        let clock = ContinuousClock()
        let start = clock.now

        // Generate 2 candidates in parallel (reduced from 3 for test speed)
        let candidates = try await VoiceDesigner.generateCandidates(
            profile: profile,
            count: 2,
            modelManager: modelManager
        )

        let elapsed = clock.now - start

        // Verify we got the requested number of candidates
        #expect(candidates.count == 2, "Should generate exactly 2 candidates")

        // Verify all candidates are valid WAV data
        for (index, candidate) in candidates.enumerated() {
            #expect(candidate.count > 0, "Candidate \(index) should not be empty")
            #expect(candidate.count > 100, "Candidate \(index) should be substantial (>100 bytes)")

            let riffHeader = candidate.prefix(4)
            let riffString = String(data: riffHeader, encoding: .ascii)
            #expect(riffString == "RIFF", "Candidate \(index) should have RIFF header")

            let waveHeader = candidate.dropFirst(8).prefix(4)
            let waveString = String(data: waveHeader, encoding: .ascii)
            #expect(waveString == "WAVE", "Candidate \(index) should be WAVE format")

            // Validate WAV sample rate (24kHz)
            if candidate.count >= 28 {
                let sampleRateBytes = candidate.dropFirst(24).prefix(4)
                let sampleRate = sampleRateBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                #expect(sampleRate == 24000, "Candidate \(index) should be 24kHz")
            }

            // Validate mono channel
            if candidate.count >= 24 {
                let channelBytes = candidate.dropFirst(22).prefix(2)
                let channels = channelBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
                #expect(channels == 1, "Candidate \(index) should be mono")
            }
        }

        // Log performance for manual inspection (not an assertion --
        // actual speedup depends on GPU scheduling and model concurrency).
        // Performance logging is also emitted by VoiceDesigner itself via stderr.
        FileHandle.standardError.write(Data(
            "[Test] Parallel generation of 2 candidates completed in \(elapsed)\n".utf8
        ))
    }

    // MARK: - VoiceLock Serialization Test

    @Test("VoiceLock clone prompt survives serialization round-trip")
    func voiceLockSerializationRoundTrip() async throws {
        let profile = CharacterProfile(
            name: "SERIALIZATION_TEST",
            gender: .female,
            ageRange: "20s",
            description: "A test character for serialization validation.",
            voiceTraits: ["bright", "energetic"],
            summary: "A young female test character."
        )

        let modelManager = VoxAltaModelManager()
        let voiceDescription = VoiceDesigner.composeVoiceDescription(from: profile)

        // Generate candidate and create lock
        let candidate = try await VoiceDesigner.generateCandidate(
            profile: profile,
            modelManager: modelManager
        )

        let voiceLock = try await VoiceLockManager.createLock(
            characterName: profile.name,
            candidateAudio: candidate,
            designInstruction: voiceDescription,
            modelManager: modelManager
        )

        // Generate audio from lock (first generation)
        let audio1 = try await VoiceLockManager.generateAudio(
            text: "Test sentence one.",
            voiceLock: voiceLock,
            language: "en",
            modelManager: modelManager
        )

        // Generate audio from same lock (second generation)
        let audio2 = try await VoiceLockManager.generateAudio(
            text: "Test sentence two.",
            voiceLock: voiceLock,
            language: "en",
            modelManager: modelManager
        )

        // Verify both generations produced valid WAV data
        #expect(audio1.count > 0, "First generation should not be empty")
        #expect(audio2.count > 0, "Second generation should not be empty")

        let riff1 = String(data: audio1.prefix(4), encoding: .ascii)
        let riff2 = String(data: audio2.prefix(4), encoding: .ascii)
        #expect(riff1 == "RIFF", "First generation should be RIFF WAV")
        #expect(riff2 == "RIFF", "Second generation should be RIFF WAV")

        // Note: We can't easily verify that the voice sounds the same without
        // decoding and comparing spectral features, but the test validates that
        // the clone prompt survives serialization and can be reused.
    }
}
