//
//  GenerationContextTests.swift
//  SwiftVoxAltaTests
//
//  Tests for GenerationContext and AnyCodableValue.
//

import Foundation
import Testing
@testable import SwiftVoxAlta

@Suite("GenerationContext Tests")
struct GenerationContextTests {

    // MARK: - Valid Construction

    @Test("Valid construction with metadata")
    func validConstructionWithMetadata() {
        let context = GenerationContext(
            phrase: "Hello world",
            metadata: [
                "pause_ms": .int(500),
                "emotion": .string("calm"),
                "speed_factor": .double(1.2),
                "whisper": .bool(true)
            ]
        )

        #expect(context.phrase == "Hello world")
        #expect(context.metadata.count == 4)
        #expect(context.metadata["pause_ms"] == .int(500))
        #expect(context.metadata["emotion"] == .string("calm"))
        #expect(context.metadata["speed_factor"] == .double(1.2))
        #expect(context.metadata["whisper"] == .bool(true))
    }

    @Test("Empty metadata is valid")
    func emptyMetadata() {
        let context = GenerationContext(phrase: "Just text")

        #expect(context.phrase == "Just text")
        #expect(context.metadata.isEmpty)
    }

    // MARK: - Key Normalization

    @Test("Already-valid snake_case keys are unchanged")
    func snakeCaseKeysUnchanged() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["emotion": .string("happy")]
        )
        #expect(context.metadata["emotion"] == .string("happy"))
    }

    @Test("Underscore-separated keys are unchanged")
    func underscoreSeparatedUnchanged() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["pause_ms": .int(100), "long_pause_duration": .int(2000)]
        )
        #expect(context.metadata.count == 2)
        #expect(context.metadata["pause_ms"] == .int(100))
        #expect(context.metadata["long_pause_duration"] == .int(2000))
    }

    @Test("camelCase keys are normalized to snake_case")
    func camelCaseNormalized() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["pauseMs": .int(500)]
        )
        #expect(context.metadata["pause_ms"] == .int(500))
        #expect(context.metadata["pauseMs"] == nil)
    }

    @Test("UPPERCASE keys are normalized to lowercase")
    func uppercaseNormalized() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["PAUSE": .int(500)]
        )
        #expect(context.metadata["pause"] == .int(500))
    }

    @Test("Keys with spaces are normalized to underscores")
    func spacesNormalized() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["pause ms": .int(500)]
        )
        #expect(context.metadata["pause_ms"] == .int(500))
    }

    @Test("Keys with hyphens are normalized to underscores")
    func hyphensNormalized() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["pause-ms": .int(500)]
        )
        #expect(context.metadata["pause_ms"] == .int(500))
    }

    @Test("PascalCase keys are normalized")
    func pascalCaseNormalized() {
        let context = GenerationContext(
            phrase: "test",
            metadata: ["PauseMs": .int(500)]
        )
        #expect(context.metadata["pause_ms"] == .int(500))
    }

    // MARK: - toSnakeCase Unit Tests

    @Test("toSnakeCase handles various input formats")
    func toSnakeCaseVariants() {
        #expect(GenerationContext.toSnakeCase("camelCase") == "camel_case")
        #expect(GenerationContext.toSnakeCase("PascalCase") == "pascal_case")
        #expect(GenerationContext.toSnakeCase("ALLCAPS") == "allcaps")
        #expect(GenerationContext.toSnakeCase("already_snake") == "already_snake")
        #expect(GenerationContext.toSnakeCase("with spaces") == "with_spaces")
        #expect(GenerationContext.toSnakeCase("with-hyphens") == "with_hyphens")
        #expect(GenerationContext.toSnakeCase("XMLParser") == "xml_parser")
        #expect(GenerationContext.toSnakeCase("") == "")
    }

    // MARK: - Serialized Size

    @Test("serializedSize is positive for non-trivial context")
    func serializedSizePositive() {
        let context = GenerationContext(
            phrase: "Hello world",
            metadata: ["emotion": .string("calm")]
        )
        #expect(context.serializedSize > 0)
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = GenerationContext(
            phrase: "Hello world",
            metadata: [
                "pause_ms": .int(500),
                "emotion": .string("calm"),
                "speed": .double(1.5),
                "whisper": .bool(false)
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GenerationContext.self, from: data)

        #expect(decoded.phrase == original.phrase)
        #expect(decoded.metadata == original.metadata)
    }

    // MARK: - AnyCodableValue

    @Test("AnyCodableValue Codable round-trip for all types")
    func anyCodableValueRoundTrip() throws {
        let values: [AnyCodableValue] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .bool(true)
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
            #expect(decoded == value)
        }
    }
}
