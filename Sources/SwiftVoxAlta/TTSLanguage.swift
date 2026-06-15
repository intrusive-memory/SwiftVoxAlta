//
//  TTSLanguage.swift
//  SwiftVoxAlta
//
//  Typed, model-aligned language identity for the generation pipeline.
//

import Foundation

/// The set of languages Qwen3-TTS can actually condition on.
///
/// These cases mirror the model's on-device `codec_language_id` keys exactly —
/// there is intentionally **no** regional sub-variant (no `en-US`/`en-GB`),
/// because the model has a single representation per language. Region/script
/// information carried by a `Locale` is therefore *lossy* at this boundary:
/// `en_GB` and `en_US` both resolve to ``english``. Callers that need a regional
/// accent must control the clone reference audio in the `.vox`, not the language.
///
/// This is the type that threads through every internal generation layer
/// (``VoxAltaVoiceProvider`` → ``VoiceLockManager`` → the model boundary),
/// replacing the previous bare `String` (defaulting to `"en"`) which never
/// resolved to a model language token and produced un-conditioned output.
public enum TTSLanguage: String, Sendable, CaseIterable, Equatable {
  case chinese
  case english
  case german
  case italian
  case portuguese
  case spanish
  case japanese
  case korean
  case french
  case russian
  case beijingDialect
  case sichuanDialect
  /// Let the model infer the language. Emits no language token (matches the
  /// historical `"en"` behavior). Only reachable when explicitly requested.
  case auto

  /// The exact key the model's `codec_language_id` map expects.
  public var modelName: String {
    switch self {
    case .beijingDialect: return "beijing_dialect"
    case .sichuanDialect: return "sichuan_dialect"
    default: return rawValue
    }
  }

  // MARK: - Resolution

  /// ISO 639-1 codes the model supports. Dialects and `auto` are explicit-only
  /// (not reachable from a plain locale).
  private static let iso639: [String: TTSLanguage] = [
    "zh": .chinese, "en": .english, "de": .german, "it": .italian,
    "pt": .portuguese, "es": .spanish, "ja": .japanese, "ko": .korean,
    "fr": .french, "ru": .russian,
  ]

  /// Full language names, model-name forms, and short dialect aliases.
  private static let aliases: [String: TTSLanguage] = [
    "english": .english, "chinese": .chinese, "german": .german,
    "italian": .italian, "portuguese": .portuguese, "spanish": .spanish,
    "japanese": .japanese, "korean": .korean, "french": .french, "russian": .russian,
    "beijing_dialect": .beijingDialect, "beijingdialect": .beijingDialect,
    "beijing": .beijingDialect,
    "sichuan_dialect": .sichuanDialect, "sichuandialect": .sichuanDialect,
    "sichuan": .sichuanDialect,
  ]

  /// Resolve from a Swift `Locale`.
  ///
  /// Extracts the language code and maps it to a supported case. Any region the
  /// locale carries (e.g. `GB` in `en_GB`) is dropped and logged in debug builds,
  /// because the model cannot represent it.
  ///
  /// - Throws: ``VoxAltaError/unsupportedLanguage(_:)`` if the locale's language
  ///   is not one the model supports.
  public init(locale: Locale) throws {
    guard let code = locale.language.languageCode?.identifier.lowercased(),
      let resolved = Self.iso639[code]
    else {
      throw VoxAltaError.unsupportedLanguage(locale.identifier)
    }
    if let region = locale.region?.identifier {
      TTSLanguage.trace(
        "resolve",
        "\(locale.identifier) → \(resolved.modelName) (dropped region \(region); "
          + "model has no regional variant)")
    }
    self = resolved
  }

  /// Resolve from an arbitrary tag: a BCP-47 locale identifier (`"en"`, `"en-GB"`,
  /// `"es-MX"`), a full language name (`"english"`), a model-name form
  /// (`"beijing_dialect"`), or the literal `"auto"`.
  ///
  /// This is the single normalization point at the SwiftHablare-facing boundary,
  /// where the protocol hands us a `String languageCode`.
  ///
  /// - Throws: ``VoxAltaError/unsupportedLanguage(_:)`` if the tag cannot be
  ///   mapped to a supported language.
  public init(languageCode raw: String) throws {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = trimmed.lowercased()
    if lowered == "auto" {
      self = .auto
      return
    }
    if let direct = Self.aliases[lowered] {
      self = direct
      return
    }
    try self.init(locale: Locale(identifier: trimmed))
  }

  // MARK: - Debug Tracing

  /// Emit a `[lang]` trace line to stderr in debug builds only.
  ///
  /// Used at each consumption site so the resolved language can be followed as it
  /// crosses the stack (provider → voice-lock → model boundary). Compiled out of
  /// release builds.
  public static func trace(_ stage: String, _ message: String) {
    #if DEBUG
      FileHandle.standardError.write(Data("[lang] \(stage): \(message)\n".utf8))
    #endif
  }

  /// Convenience: log this language being consumed at `stage` with optional context.
  public func logConsumption(stage: String, detail: String = "") {
    let extra = detail.isEmpty ? "" : " — \(detail)"
    TTSLanguage.trace(stage, "\(modelName)\(extra)")
  }
}
