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

    @Test("fetchVoices returns empty when no voices loaded")
    func fetchVoicesEmpty() async throws {
        let provider = VoxAltaVoiceProvider()
        let voices = try await provider.fetchVoices(languageCode: "en")
        #expect(voices.isEmpty)
    }

    @Test("loadVoice + fetchVoices returns correct Voice objects")
    func loadAndFetch() async throws {
        let provider = VoxAltaVoiceProvider()
        let cloneData = Data([0x01, 0x02, 0x03])

        await provider.loadVoice(id: "ELENA", clonePromptData: cloneData, gender: "female")

        let voices = try await provider.fetchVoices(languageCode: "en")
        #expect(voices.count == 1)

        let voice = voices[0]
        #expect(voice.id == "ELENA")
        #expect(voice.name == "ELENA")
        #expect(voice.providerId == "voxalta")
        #expect(voice.language == "en")
        #expect(voice.gender == "female")
        #expect(voice.description == "VoxAlta on-device voice")
    }

    @Test("loadVoice with multiple voices")
    func loadMultiple() async throws {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]), gender: "female")
        await provider.loadVoice(id: "MARCUS", clonePromptData: Data([0x02]), gender: "male")

        let voices = try await provider.fetchVoices(languageCode: "es")
        #expect(voices.count == 2)

        let ids = Set(voices.map { $0.id })
        #expect(ids.contains("ELENA"))
        #expect(ids.contains("MARCUS"))

        // Verify language is passed through
        for voice in voices {
            #expect(voice.language == "es")
        }
    }

    @Test("isVoiceAvailable returns true for loaded voice")
    func voiceAvailableAfterLoad() async {
        let provider = VoxAltaVoiceProvider()

        await provider.loadVoice(id: "ELENA", clonePromptData: Data([0x01]))

        let available = await provider.isVoiceAvailable(voiceId: "ELENA")
        #expect(available == true)
    }

    @Test("isVoiceAvailable returns false for unloaded voice")
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

    @Test("unloadAllVoices clears all voices")
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
        #expect(voices?.isEmpty == true)
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
