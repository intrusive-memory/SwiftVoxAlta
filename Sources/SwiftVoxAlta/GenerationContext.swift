//
//  GenerationContext.swift
//  SwiftVoxAlta
//
//  Envelope carrying a phrase and optional metadata through the generation pipeline.
//

import Foundation

/// Type-erased `Codable` value for generation metadata entries.
///
/// Supports the primitive types needed for generation hints (strings, integers,
/// doubles, booleans). Conforms to `Sendable` for safe passage across isolation
/// boundaries.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodableValue: unsupported type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

/// Envelope carrying a phrase and optional metadata through the TTS generation pipeline.
///
/// `GenerationContext` consolidates the text-to-synthesize with structured hints
/// (e.g., parenthetical pacing, emotion tags) into a single value that threads
/// through `VoiceLockManager`, `VoxAltaVoiceProvider`, and `DigaEngine`.
///
/// Metadata keys are automatically normalized to lowercase snake_case.
/// For example, `"pauseMs"` becomes `"pause_ms"`, `"LOUD"` becomes `"loud"`.
public struct GenerationContext: Codable, Sendable {

    /// The text to synthesize.
    public let phrase: String

    /// Optional key-value metadata for generation hints.
    /// Keys are normalized to lowercase snake_case on construction.
    public let metadata: [String: AnyCodableValue]

    /// Create a generation context.
    ///
    /// - Parameters:
    ///   - phrase: The text to synthesize.
    ///   - metadata: Optional key-value pairs. Keys are automatically normalized
    ///     to lowercase snake_case.
    public init(phrase: String, metadata: [String: AnyCodableValue] = [:]) {
        self.phrase = phrase
        var normalized: [String: AnyCodableValue] = [:]
        for (key, value) in metadata {
            normalized[Self.toSnakeCase(key)] = value
        }
        self.metadata = normalized
    }

    /// JSON-encoded byte count, useful for logging envelope sizes.
    public var serializedSize: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }

    /// Convert an arbitrary string to lowercase snake_case.
    ///
    /// Handles camelCase, PascalCase, UPPERCASE, spaces, hyphens, and mixed styles.
    static func toSnakeCase(_ input: String) -> String {
        guard !input.isEmpty else { return input }

        var result = ""
        let chars = Array(input)
        for (i, char) in chars.enumerated() {
            if char.isUppercase {
                // Insert underscore before an uppercase letter when preceded by
                // a lowercase letter or digit, or when followed by a lowercase letter
                // (handles "XMLParser" → "xml_parser").
                if i > 0 {
                    let prev = chars[i - 1]
                    let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                    if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                        result.append("_")
                    }
                }
                result.append(char.lowercased())
            } else if char == " " || char == "-" {
                result.append("_")
            } else {
                result.append(char)
            }
        }

        // Collapse multiple underscores and trim edges.
        let collapsed = result.split(separator: "_", omittingEmptySubsequences: true).joined(separator: "_")
        return collapsed
    }
}
