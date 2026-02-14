//
//  VoxAltaVoiceProviderTests.swift
//  SwiftVoxAltaTests
//
//  Tests for VoxAltaVoiceProvider conformance and VoxAltaProviderDescriptor.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

// MARK: - Provider Metadata

@Suite("VoxAltaVoiceProvider - Metadata")
struct VoxAltaVoiceProviderMetadataTests {

    @Test("providerId is voxalta")
    func providerId() {
        let provider = VoxAltaVoiceProvider()
        #expect(provider.providerId == "voxalta")
    }

    @Test("displayName is VoxAlta (On-Device)")
    func displayName() {
        let provider = VoxAltaVoiceProvider()
        #expect(provider.displayName == "VoxAlta (On-Device)")
    }

    @Test("requiresAPIKey is false")
    func requiresAPIKey() {
        let provider = VoxAltaVoiceProvider()
        #expect(provider.requiresAPIKey == false)
    }

    @Test("mimeType is audio/wav")
    func mimeType() {
        let provider = VoxAltaVoiceProvider()
        #expect(provider.mimeType == "audio/wav")
    }

    @Test("defaultVoiceId is nil")
    func defaultVoiceId() {
        let provider = VoxAltaVoiceProvider()
        #expect(provider.defaultVoiceId == nil)
    }
}

// MARK: - Configuration

@Suite("VoxAltaVoiceProvider - Configuration")
struct VoxAltaVoiceProviderConfigTests {

    @Test("isConfigured returns true")
    func isConfigured() async {
        let provider = VoxAltaVoiceProvider()
        let configured = await provider.isConfigured()
        #expect(configured == true)
    }
}

// MARK: - Voice Loading and Fetching

@Suite("VoxAltaVoiceProvider - Voice Management")
struct VoxAltaVoiceProviderVoiceTests {

    @Test("Fetch voices returns all 9 preset speakers")
    func testFetchVoicesReturnsPresetSpeakers() async throws {
        let provider = VoxAltaVoiceProvider()
        let voices = try await provider.fetchVoices(languageCode: "en")

        #expect(voices.count >= 9, "Should return at least 9 preset speakers")

        let presetIds = ["ryan", "aiden", "vivian", "serena", "uncle_fu", "dylan", "eric", "anna", "sohee"]
        for id in presetIds {
            #expect(voices.contains { $0.id == id }, "Missing preset speaker: \(id)")
        }
    }

    @Test("loadVoice + fetchVoices returns preset speakers plus custom voices")
    func loadAndFetch() async throws {
        let provider = VoxAltaVoiceProvider()
        let cloneData = Data([0x01, 0x02, 0x03])

        await provider.loadVoice(id: "ELENA", clonePromptData: cloneData, gender: "female")

        let voices = try await provider.fetchVoices(languageCode: "en")
        #expect(voices.count == 10, "Should return 9 preset speakers + 1 custom voice")

        // Find the custom voice
        let customVoice = voices.first { $0.id == "ELENA" }
        #expect(customVoice != nil, "Custom voice ELENA should be in the list")
        #expect(customVoice?.name == "ELENA")
        #expect(customVoice?.providerId == "voxalta")
        #expect(customVoice?.language == "en")
        #expect(customVoice?.gender == "female")
        #expect(customVoice?.description == "VoxAlta on-device voice")
    }

    @Test("loadVoice with multiple voices")
    func loadMultiple() async throws {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]), gender: "female")
        await provider.loadVoice(id: "MARCUS", clonePromptData: Data([0x02]), gender: "male")

        let voices = try await provider.fetchVoices(languageCode: "es")
        #expect(voices.count == 11, "Should return 9 preset speakers + 2 custom voices")

        let ids = Set(voices.map { $0.id })
        #expect(ids.contains("ELENA"))
        #expect(ids.contains("MARCUS"))

        // Verify language is passed through
        for voice in voices {
            #expect(voice.language == "es")
        }
    }

    @Test("Preset speakers are always available")
    func testIsVoiceAvailableForPresets() async {
        let provider = VoxAltaVoiceProvider()

        let available = await provider.isVoiceAvailable(voiceId: "ryan")
        #expect(available == true, "Preset speaker 'ryan' should always be available")

        let unavailable = await provider.isVoiceAvailable(voiceId: "nonexistent_voice")
        #expect(unavailable == false, "Non-preset voice should not be available")
    }

    @Test("isVoiceAvailable returns true for loaded voice")
    func voiceAvailableAfterLoad() async {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]))

        let available = await provider.isVoiceAvailable(voiceId: "ELENA")
        #expect(available == true)
    }

    @Test("isVoiceAvailable returns false for unloaded custom voice")
    func voiceNotAvailableWhenNotLoaded() async {
        let provider = VoxAltaVoiceProvider()

        let available = await provider.isVoiceAvailable(voiceId: "NOBODY")
        #expect(available == false)
    }

    @Test("unloadVoice removes the voice")
    func unloadVoice() async {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]))
        await provider.unloadVoice(id: "ELENA")

        let available = await provider.isVoiceAvailable(voiceId: "ELENA")
        #expect(available == false)

        let voices = try? await provider.fetchVoices(languageCode: "en")
        #expect(voices?.isEmpty == true)
    }

    @Test("unloadAllVoices clears custom voices but presets remain")
    func unloadAllVoices() async {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]))
        await provider.loadVoice(id: "MARCUS", clonePromptData: Data([0x02]))
        await provider.unloadAllVoices()

        let available1 = await provider.isVoiceAvailable(voiceId: "ELENA")
        let available2 = await provider.isVoiceAvailable(voiceId: "MARCUS")
        #expect(available1 == false)
        #expect(available2 == false)

        let voices = try? await provider.fetchVoices(languageCode: "en")
        #expect(voices?.count == 9, "Should still have 9 preset speakers")
    }

    @Test("Dual-mode routing: preset vs clone prompt")
    func testDualModeRouting() async throws {
        let provider = VoxAltaVoiceProvider()

        // Test clone prompt route (should throw since no voice loaded)
        await #expect(throws: VoxAltaError.self) {
            try await provider.generateAudio(
                text: "Clone test",
                voiceId: "custom_voice_123",
                languageCode: "en"
            )
        }
    }

    @Test("Generate audio with preset speaker 'ryan'")
    func testGenerateAudioWithPresetSpeaker() async throws {
        let provider = VoxAltaVoiceProvider()
        let audio = try await provider.generateAudio(
            text: "Hello from Ryan",
            voiceId: "ryan",
            languageCode: "en"
        )

        #expect(audio.count > 44, "WAV should be larger than 44-byte header")

        // Validate WAV format
        let riff = String(data: audio[0..<4], encoding: .ascii)
        #expect(riff == "RIFF", "Should be WAV format (RIFF header)")
    }

    @Test("Generate audio with all 9 preset speakers")
    func testGenerateAudioWithAllPresetSpeakers() async throws {
        let provider = VoxAltaVoiceProvider()
        let presetIds = ["ryan", "aiden", "vivian", "serena", "uncle_fu", "dylan", "eric", "anna", "sohee"]

        for id in presetIds {
            let audio = try await provider.generateAudio(
                text: "Testing voice \(id)",
                voiceId: id,
                languageCode: "en"
            )
            #expect(audio.count > 44, "Speaker \(id) should generate valid audio")
        }
    }

    @Test("Generated audio has expected duration")
    func testGenerateProcessedAudioDuration() async throws {
        let provider = VoxAltaVoiceProvider()
        let text = "This is a test sentence."

        let audio = try await provider.generateAudio(
            text: text,
            voiceId: "ryan",
            languageCode: "en"
        )

        // Parse WAV header to get duration
        let duration = try parseWAVDuration(audio)

        // Expect ~1-3 seconds for a short sentence
        #expect(duration > 0.5, "Audio should be at least 0.5 seconds")
        #expect(duration < 10.0, "Audio should be less than 10 seconds for short text")
    }
}

// MARK: - Audio Generation

@Suite("VoxAltaVoiceProvider - Audio Generation")
struct VoxAltaVoiceProviderAudioTests {

    @Test("generateAudio throws voiceNotLoaded for unloaded voice")
    func generateAudioThrowsForUnloadedVoice() async {
        let provider = VoxAltaVoiceProvider()

        do {
            _ = try await provider.generateAudio(
                text: "Hello",
                voiceId: "NONEXISTENT",
                languageCode: "en"
            )
            Issue.record("Expected generateAudio to throw for unloaded voice")
        } catch let error as VoxAltaError {
            if case .voiceNotLoaded(let voiceId) = error {
                #expect(voiceId == "NONEXISTENT")
            } else {
                Issue.record("Expected voiceNotLoaded error, got \(error)")
            }
        } catch {
            Issue.record("Expected VoxAltaError, got \(type(of: error)): \(error)")
        }
    }

    @Test("generateAudio with loaded voice gets past cache lookup")
    func generateAudioWithLoadedVoicePassesCacheLookup() async {
        let provider = VoxAltaVoiceProvider()
        let fakeCloneData = Data([0x01, 0x02, 0x03])

        await provider.loadVoice(id: "ELENA", clonePromptData: fakeCloneData, gender: "female")

        // This should not throw voiceNotLoaded — it should get past the cache lookup
        // and fail on model loading instead
        do {
            _ = try await provider.generateAudio(
                text: "Hello",
                voiceId: "ELENA",
                languageCode: "en"
            )
            Issue.record("Expected generateAudio to throw without a loaded model")
        } catch let error as VoxAltaError {
            // Should be a model-related error, NOT voiceNotLoaded
            if case .voiceNotLoaded = error {
                Issue.record("Should not be voiceNotLoaded — voice was loaded")
            }
            // Any other VoxAltaError is expected (modelNotAvailable, cloningFailed, etc.)
        } catch {
            // Other errors from mlx-audio-swift are also acceptable
        }
    }
}

// MARK: - Duration Estimation

@Suite("VoxAltaVoiceProvider - Duration Estimation")
struct VoxAltaVoiceProviderDurationTests {

    @Test("estimateDuration with known text")
    func estimateDuration() async {
        let provider = VoxAltaVoiceProvider()

        // "Hello world" = 2 words
        // 2 / 150 * 60 = 0.8 seconds
        let duration = await provider.estimateDuration(text: "Hello world", voiceId: "ELENA")
        #expect(duration > 0.79)
        #expect(duration < 0.81)
    }

    @Test("estimateDuration with longer text")
    func estimateDurationLonger() async {
        let provider = VoxAltaVoiceProvider()

        // 150 words should be approximately 60 seconds
        let words = Array(repeating: "word", count: 150).joined(separator: " ")
        let duration = await provider.estimateDuration(text: words, voiceId: "ELENA")
        #expect(duration > 59.0)
        #expect(duration < 61.0)
    }

    @Test("estimateDuration with empty text returns zero")
    func estimateDurationEmpty() async {
        let provider = VoxAltaVoiceProvider()

        let duration = await provider.estimateDuration(text: "", voiceId: "ELENA")
        #expect(duration == 0.0)
    }

    @Test("estimateDuration with single word")
    func estimateDurationSingleWord() async {
        let provider = VoxAltaVoiceProvider()

        // 1 / 150 * 60 = 0.4 seconds
        let duration = await provider.estimateDuration(text: "Hello", voiceId: "ELENA")
        #expect(duration > 0.39)
        #expect(duration < 0.41)
    }
}

// MARK: - WAV Duration Measurement

@Suite("VoxAltaVoiceProvider - WAV Duration Measurement")
struct VoxAltaVoiceProviderWAVDurationTests {

    @Test("measureWAVDuration with valid WAV data")
    func measureValidWAV() {
        // Build a valid WAV with known parameters:
        // 24000 Hz, mono, 16-bit, 24000 samples = 1.0 second
        let sampleCount = 24000
        let samples = [Int16](repeating: 0, count: sampleCount)
        let wavData = AudioConversion.buildWAVData(pcmSamples: samples, sampleRate: 24000)

        let duration = VoxAltaVoiceProvider.measureWAVDuration(wavData)
        #expect(duration > 0.99)
        #expect(duration < 1.01)
    }

    @Test("measureWAVDuration with half-second WAV")
    func measureHalfSecondWAV() {
        // 12000 samples at 24000 Hz = 0.5 seconds
        let samples = [Int16](repeating: 0, count: 12000)
        let wavData = AudioConversion.buildWAVData(pcmSamples: samples, sampleRate: 24000)

        let duration = VoxAltaVoiceProvider.measureWAVDuration(wavData)
        #expect(duration > 0.49)
        #expect(duration < 0.51)
    }

    @Test("measureWAVDuration returns 0 for invalid data")
    func measureInvalidData() {
        let duration = VoxAltaVoiceProvider.measureWAVDuration(Data([0x00, 0x01]))
        #expect(duration == 0.0)
    }

    @Test("measureWAVDuration returns 0 for empty data")
    func measureEmptyData() {
        let duration = VoxAltaVoiceProvider.measureWAVDuration(Data())
        #expect(duration == 0.0)
    }

    @Test("measureWAVDuration returns 0 for non-WAV data")
    func measureNonWAVData() {
        let data = Data(repeating: 0xAA, count: 100)
        let duration = VoxAltaVoiceProvider.measureWAVDuration(data)
        #expect(duration == 0.0)
    }
}

// MARK: - Provider Descriptor

@Suite("VoxAltaProviderDescriptor")
struct VoxAltaProviderDescriptorTests {

    @Test("Descriptor has correct metadata")
    func descriptorMetadata() {
        let descriptor = VoxAltaProviderDescriptor.descriptor()

        #expect(descriptor.id == "voxalta")
        #expect(descriptor.displayName == "VoxAlta (On-Device)")
        #expect(descriptor.isEnabledByDefault == false)
        #expect(descriptor.requiresConfiguration == true)
    }

    @Test("Descriptor factory creates provider with correct providerId")
    func descriptorCreatesProvider() {
        let descriptor = VoxAltaProviderDescriptor.descriptor()
        let provider = descriptor.makeProvider()

        #expect(provider.providerId == "voxalta")
        #expect(provider.displayName == "VoxAlta (On-Device)")
    }

    @Test("Descriptor factory creates VoxAltaVoiceProvider instance")
    func descriptorCreatesCorrectType() {
        let descriptor = VoxAltaProviderDescriptor.descriptor()
        let provider = descriptor.makeProvider()

        let isVoxAlta = provider is VoxAltaVoiceProvider
        #expect(isVoxAlta)
    }

    @Test("Descriptor accepts custom model manager")
    func descriptorWithCustomModelManager() {
        let manager = VoxAltaModelManager()
        let descriptor = VoxAltaProviderDescriptor.descriptor(modelManager: manager)

        let provider = descriptor.makeProvider()
        #expect(provider.providerId == "voxalta")
    }

    @Test("Descriptor factory creates distinct instances")
    func descriptorFactoryCreatesDistinctInstances() {
        let descriptor = VoxAltaProviderDescriptor.descriptor()

        let provider1 = descriptor.makeProvider() as! VoxAltaVoiceProvider
        let provider2 = descriptor.makeProvider() as! VoxAltaVoiceProvider

        // They should be different class instances
        #expect(provider1 !== provider2)
    }
}

// MARK: - Sendable Conformance

@Suite("VoxAltaVoiceProvider - Sendable")
struct VoxAltaVoiceProviderSendableTests {

    @Test("VoxAltaVoiceProvider is Sendable")
    func providerIsSendable() {
        let provider: any Sendable = VoxAltaVoiceProvider()
        #expect(provider is VoxAltaVoiceProvider)
    }

    @Test("VoxAltaProviderDescriptor enum is Sendable")
    func descriptorEnumIsSendable() {
        let _: any Sendable.Type = VoxAltaProviderDescriptor.self
    }
}

// MARK: - Test Helpers

/// Parse WAV duration from audio data.
/// - Location: Private helper in this test file only
private func parseWAVDuration(_ wavData: Data) throws -> Double {
    // Parse WAV header (44 bytes)
    guard wavData.count > 44 else {
        throw VoxAltaError.audioExportFailed("WAV data too small, expected at least 44 bytes header")
    }

    // Sample rate at bytes 24-27 (little-endian)
    let sampleRate = wavData[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }

    // Data chunk size at bytes 40-43 (little-endian)
    let dataSize = wavData[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }

    // Duration = dataSize / (sampleRate * channels * bytesPerSample)
    // For 16-bit mono: dataSize / (sampleRate * 1 * 2)
    return Double(dataSize) / Double(sampleRate * 2)
}
