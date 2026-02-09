//
//  ConsistencyTests.swift
//  SwiftVoxAltaTests
//
//  Voice consistency validation tests: round-trip serialization, audio conversion
//  fidelity, voice description determinism, and parenthetical mapping consistency.
//

import Foundation
import Testing
@preconcurrency import MLX
@testable import SwiftVoxAlta

// MARK: - VoiceLock Round-Trip Tests

@Suite("Consistency - VoiceLock Round-Trip")
struct VoiceLockRoundTripTests {

    @Test("VoiceLock round-trips through JSON: all fields match")
    func voiceLockJSONRoundTrip() throws {
        let cloneData = Data((0..<1024).map { UInt8($0 % 256) })
        let lockDate = Date(timeIntervalSince1970: 1_700_000_000)

        let original = VoiceLock(
            characterName: "ELENA",
            clonePromptData: cloneData,
            designInstruction: "A warm female voice in her 30s with slightly husky quality.",
            lockedAt: lockDate
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == original.characterName)
        #expect(decoded.clonePromptData == original.clonePromptData)
        #expect(decoded.designInstruction == original.designInstruction)
        #expect(decoded.lockedAt == original.lockedAt)
    }

    @Test("VoiceLock round-trips through PropertyList: all fields match")
    func voiceLockPlistRoundTrip() throws {
        let cloneData = Data((0..<512).map { UInt8($0 % 256) })
        let lockDate = Date()

        let original = VoiceLock(
            characterName: "MARCUS",
            clonePromptData: cloneData,
            designInstruction: "A deep male voice, 40s, measured and calm.",
            lockedAt: lockDate
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == original.characterName)
        #expect(decoded.clonePromptData == original.clonePromptData)
        #expect(decoded.designInstruction == original.designInstruction)
        // Date comparison: PropertyList may lose sub-millisecond precision
        #expect(abs(decoded.lockedAt.timeIntervalSince(original.lockedAt)) < 0.001)
    }

    @Test("VoiceLock preserves large clone prompt data integrity")
    func voiceLockLargeCloneData() throws {
        // Simulate a realistic clone prompt (16 KB)
        let largeData = Data((0..<16384).map { UInt8($0 % 256) })

        let original = VoiceLock(
            characterName: "NARRATOR",
            clonePromptData: largeData,
            designInstruction: "Omniscient narrator voice."
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.clonePromptData.count == 16384)
        #expect(decoded.clonePromptData == largeData,
                "Large clone prompt data should be perfectly preserved through serialization")
    }

    @Test("VoiceLock with empty clone data round-trips")
    func voiceLockEmptyCloneData() throws {
        let original = VoiceLock(
            characterName: "PHANTOM",
            clonePromptData: Data(),
            designInstruction: ""
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceLock.self, from: encoded)

        #expect(decoded.characterName == "PHANTOM")
        #expect(decoded.clonePromptData.isEmpty)
        #expect(decoded.designInstruction.isEmpty)
    }
}

// MARK: - AudioConversion Round-Trip Tests

@Suite("Consistency - AudioConversion Round-Trip")
struct AudioConversionRoundTripTests {

    @Test("MLXArray to WAV to MLXArray preserves sample values within quantization error")
    func audioRoundTripPreservesValues() throws {
        let originalSamples: [Float] = [0.0, 0.1, -0.1, 0.5, -0.5, 0.9, -0.9]
        let original = MLXArray(originalSamples)

        let wavData = try AudioConversion.mlxArrayToWAVData(original)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let restoredSamples = restored.asArray(Float.self)

        // 16-bit quantization error is at most 1/32767
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6

        #expect(restoredSamples.count == originalSamples.count,
                "Sample count should be preserved")

        for (i, orig) in originalSamples.enumerated() {
            let diff = abs(restoredSamples[i] - orig)
            #expect(diff < maxError,
                    "Sample \(i): expected ~\(orig), got \(restoredSamples[i]), diff=\(diff)")
        }
    }

    @Test("Round-trip preserves sample count for various lengths")
    func audioRoundTripPreservesCount() throws {
        for count in [1, 10, 100, 1000, 24000] {
            let samples = (0..<count).map { Float(sin(Double($0) * 0.01)) }
            let original = MLXArray(samples)

            let wavData = try AudioConversion.mlxArrayToWAVData(original, sampleRate: 24000)
            let restored = try AudioConversion.wavDataToMLXArray(wavData)

            #expect(restored.size == count,
                    "Round-trip should preserve \(count) samples, got \(restored.size)")
        }
    }

    @Test("Double round-trip maintains fidelity within quantization")
    func doubleRoundTripMaintainsFidelity() throws {
        let originalSamples: [Float] = [0.3, -0.7, 0.0, 0.99, -0.99]
        let original = MLXArray(originalSamples)

        // First round-trip
        let wav1 = try AudioConversion.mlxArrayToWAVData(original)
        let restored1 = try AudioConversion.wavDataToMLXArray(wav1)

        // Second round-trip
        let wav2 = try AudioConversion.mlxArrayToWAVData(restored1)
        let restored2 = try AudioConversion.wavDataToMLXArray(wav2)

        let samples1 = restored1.asArray(Float.self)
        let samples2 = restored2.asArray(Float.self)

        // After the first quantization, subsequent round-trips should be lossless
        // because the values are already quantized to 16-bit grid
        let maxError: Float = 1.0 / Float(Int16.max) + 1e-6
        for i in 0..<samples1.count {
            let diff = abs(samples1[i] - samples2[i])
            #expect(diff < maxError,
                    "Double round-trip sample \(i): first=\(samples1[i]), second=\(samples2[i])")
        }
    }

    @Test("Round-trip of sine wave preserves waveform shape")
    func sineWaveRoundTrip() throws {
        let sampleRate = 24000
        let frequency: Float = 440.0
        let duration = 0.1  // 100ms
        let sampleCount = Int(Double(sampleRate) * duration)

        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = 0.8 * sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
        }

        let original = MLXArray(samples)
        let wavData = try AudioConversion.mlxArrayToWAVData(original, sampleRate: sampleRate)
        let restored = try AudioConversion.wavDataToMLXArray(wavData)

        let restoredSamples = restored.asArray(Float.self)
        #expect(restoredSamples.count == sampleCount)

        // Check that the waveform shape is preserved (correlation)
        var dotProduct: Float = 0
        var origNorm: Float = 0
        var restNorm: Float = 0
        for i in 0..<sampleCount {
            dotProduct += samples[i] * restoredSamples[i]
            origNorm += samples[i] * samples[i]
            restNorm += restoredSamples[i] * restoredSamples[i]
        }

        let correlation = dotProduct / (sqrt(origNorm) * sqrt(restNorm) + 1e-10)
        #expect(correlation > 0.999,
                "Sine wave correlation should be very high, got \(correlation)")
    }
}

// MARK: - VoiceDesigner Consistency Tests

@Suite("Consistency - VoiceDesigner Descriptions")
struct VoiceDesignerConsistencyTests {

    @Test("Same profile always produces the same description (deterministic)")
    func sameProfileSameDescription() {
        let profile = CharacterProfile(
            name: "ELENA",
            gender: .female,
            ageRange: "30s",
            description: "A confident journalist.",
            voiceTraits: ["warm", "confident"],
            summary: "A female journalist in her 30s."
        )

        let description1 = VoiceDesigner.composeVoiceDescription(from: profile)
        let description2 = VoiceDesigner.composeVoiceDescription(from: profile)

        #expect(description1 == description2,
                "Same profile should always produce identical descriptions")
    }

    @Test("Different profiles produce different descriptions")
    func differentProfilesDifferentDescriptions() {
        let profiles = [
            CharacterProfile(
                name: "ELENA",
                gender: .female,
                ageRange: "30s",
                description: "Journalist.",
                voiceTraits: ["warm", "confident"],
                summary: "Female journalist in her 30s."
            ),
            CharacterProfile(
                name: "MARCUS",
                gender: .male,
                ageRange: "40s",
                description: "Detective.",
                voiceTraits: ["deep", "gruff"],
                summary: "Male detective in his 40s."
            ),
            CharacterProfile(
                name: "ZOE",
                gender: .nonBinary,
                ageRange: "20s",
                description: "Hacker.",
                voiceTraits: ["quick", "energetic"],
                summary: "Non-binary hacker in their 20s."
            ),
            CharacterProfile(
                name: "NARRATOR",
                gender: .unknown,
                ageRange: "ageless",
                description: "Omniscient narrator.",
                voiceTraits: ["smooth", "authoritative"],
                summary: "An ageless, authoritative narrator."
            ),
        ]

        var descriptions = Set<String>()
        for profile in profiles {
            let desc = VoiceDesigner.composeVoiceDescription(from: profile)
            descriptions.insert(desc)
        }

        #expect(descriptions.count == profiles.count,
                "Each distinct profile should produce a unique description")
    }

    @Test("Description format is consistent across gender variants")
    func genderVariantFormatConsistency() {
        let genders: [(Gender, String)] = [
            (.male, "male"),
            (.female, "female"),
            (.nonBinary, "non-binary"),
            (.unknown, "neutral"),
        ]

        for (gender, expectedWord) in genders {
            let profile = CharacterProfile(
                name: "TEST",
                gender: gender,
                ageRange: "30s",
                description: "Test.",
                voiceTraits: ["clear"],
                summary: "A test voice."
            )

            let description = VoiceDesigner.composeVoiceDescription(from: profile)
            #expect(description.hasPrefix("A \(expectedWord) voice, 30s."),
                    "Description for \(gender) should start with 'A \(expectedWord) voice, 30s.'")
        }
    }
}

// MARK: - ParentheticalMapper Consistency Tests

@Suite("Consistency - ParentheticalMapper")
struct ParentheticalMapperConsistencyTests {

    @Test("Same input always produces the same output")
    func sameInputSameOutput() {
        let testCases = [
            "(whispering)",
            "(shouting)",
            "(sarcastic)",
            "(beat)",
            "(turning)",
            "(unknown thing)",
            "",
        ]

        for input in testCases {
            let result1 = ParentheticalMapper.mapToInstruct(input)
            let result2 = ParentheticalMapper.mapToInstruct(input)
            #expect(result1 == result2,
                    "mapToInstruct should be deterministic for input '\(input)'")
        }
    }

    @Test("Normalize function is idempotent")
    func normalizeIsIdempotent() {
        let testCases = [
            "(Whispering)",
            "(BEAT)",
            "softly",
            "(  to herself  )",
            "",
        ]

        for input in testCases {
            let once = ParentheticalMapper.normalize(input)
            let twice = ParentheticalMapper.normalize(once)
            #expect(once == twice,
                    "Normalizing '\(input)' twice should equal normalizing once: '\(once)' vs '\(twice)'")
        }
    }

    @Test("Case variations produce identical results")
    func caseVariationsIdentical() {
        let variations = [
            ("(whispering)", "(WHISPERING)", "(Whispering)", "(wHiSpErInG)"),
            ("(shouting)", "(SHOUTING)", "(Shouting)", "(SHOUTING)"),
            ("(beat)", "(BEAT)", "(Beat)", "(BEAT)"),
        ]

        for (v1, v2, v3, v4) in variations {
            let r1 = ParentheticalMapper.mapToInstruct(v1)
            let r2 = ParentheticalMapper.mapToInstruct(v2)
            let r3 = ParentheticalMapper.mapToInstruct(v3)
            let r4 = ParentheticalMapper.mapToInstruct(v4)

            #expect(r1 == r2, "'\(v1)' and '\(v2)' should produce same result")
            #expect(r2 == r3, "'\(v2)' and '\(v3)' should produce same result")
            #expect(r3 == r4, "'\(v3)' and '\(v4)' should produce same result")
        }
    }

    @Test("All vocal mappings produce non-empty strings")
    func vocalMappingsProduceNonEmpty() {
        let vocalParentheticals = [
            "(whispering)", "(shouting)", "(sarcastic)", "(angrily)",
            "(softly)", "(laughing)", "(crying)", "(nervously)",
            "(excited)", "(monotone)", "(singing)", "(to herself)",
            "(yelling)", "(quietly)", "(pleading)", "(coldly)",
            "(cheerfully)", "(sadly)", "(fearfully)", "(firmly)",
        ]

        for p in vocalParentheticals {
            let result = ParentheticalMapper.mapToInstruct(p)
            #expect(result != nil, "'\(p)' should produce a non-nil instruct")
            #expect(!result!.isEmpty, "'\(p)' should produce a non-empty instruct")
        }
    }

    @Test("All blocking parentheticals return nil")
    func blockingParentheticalsReturnNil() {
        let blockingParentheticals = [
            "(beat)", "(pause)", "(turning)", "(walking away)",
            "(standing)", "(sitting)", "(entering)", "(exiting)",
            "(crossing)", "(nodding)", "(pointing)", "(into phone)",
            "(reading)", "(writing)",
        ]

        for p in blockingParentheticals {
            let result = ParentheticalMapper.mapToInstruct(p)
            #expect(result == nil, "'\(p)' should return nil (blocking)")
        }
    }
}
