//
//  VoxAltaModelSize.swift
//  SwiftVoxAlta
//
//  The Qwen3-TTS model size VoxAlta renders with, as chosen through the
//  SwiftHablare `PluginConfiguration` (`model_size`: "1.7b" default, "0.6b").
//

import Foundation
import SwiftHablare

/// The Qwen3-TTS parameter count VoxAlta renders with.
///
/// Each size maps to two model repos: the Base model (clone-prompt voices from `.vox`
/// files) and the CustomVoice model (the nine preset speakers).
public enum VoxAltaModelSize: String, CaseIterable, Sendable, Hashable {
  /// Qwen3-TTS 1.7B (bf16). The default.
  case large = "1.7b"
  /// Qwen3-TTS 0.6B (bf16). Lighter and faster; suited to draft renders.
  case small = "0.6b"

  /// The size used when the plugin configuration names none.
  public static let `default`: VoxAltaModelSize = .large

  /// The `.vox` model slug (`embeddings/qwen3-tts/<slug>/clone-prompt.bin`).
  public var slug: String { rawValue }

  /// Base model for clone-prompt (`.vox`) synthesis.
  public var baseRepo: Qwen3TTSModelRepo {
    switch self {
    case .large: return .base1_7B
    case .small: return .base0_6B
    }
  }

  /// CustomVoice model for preset-speaker synthesis.
  public var customVoiceRepo: Qwen3TTSModelRepo {
    switch self {
    case .large: return .customVoice1_7B
    case .small: return .customVoice0_6B
    }
  }

  /// Hablare model descriptor of the Base model (id = the slug, e.g. `"1.7b"`).
  public var baseModel: ModelDescriptor {
    ModelDescriptor(
      id: slug,
      displayName: "Qwen3-TTS \(baseRepo.displayName)",
      kind: .local,
      languages: VoxAltaModelSize.languages,
      capabilities: VoxAltaSynthesizer.supportedCapabilities,
      minimumMemoryBytes: self == .large ? 3_400_000_000 : 1_200_000_000,
      acervoModelId: baseRepo.rawValue)
  }

  /// Hablare model descriptor of the CustomVoice model (id e.g. `"1.7b-customvoice"`).
  public var customVoiceModel: ModelDescriptor {
    ModelDescriptor(
      id: "\(slug)-customvoice",
      displayName: "Qwen3-TTS \(customVoiceRepo.displayName)",
      kind: .local,
      languages: VoxAltaModelSize.languages,
      capabilities: VoxAltaSynthesizer.supportedCapabilities,
      minimumMemoryBytes: self == .large ? 3_400_000_000 : 1_200_000_000,
      acervoModelId: customVoiceRepo.rawValue)
  }

  /// Languages Qwen3-TTS conditions on (BCP-47 base codes).
  static let languages = ["zh", "en", "de", "it", "pt", "es", "ja", "ko", "fr", "ru"]

  // MARK: - PluginConfiguration

  /// The `PluginConfiguration` key that selects the model size.
  public static let configurationKey = "model_size"

  /// The per-plugin setting definition for ``configurationKey``.
  public static let settingDefinition = SettingDefinition(
    key: configurationKey,
    valueType: .choice,
    choices: allCases.map(\.rawValue),
    defaultValue: .choice(VoxAltaModelSize.default.rawValue),
    scope: .perPlugin,
    label: "Model size",
    help: "Qwen3-TTS model size: 1.7b (best quality, default) or 0.6b (faster, lighter).")

  /// Reads the model size from a plugin configuration.
  ///
  /// A missing key yields ``default``. Accepts `.choice` or `.string` values,
  /// case-insensitively. Throws `HablareError.invalidRequest` for an unknown size.
  public init(configuration: PluginConfiguration) throws {
    guard let value = configuration.settings[Self.configurationKey] else {
      self = .default
      return
    }
    let raw: String
    switch value {
    case .choice(let text), .string(let text): raw = text
    default:
      throw HablareError.invalidRequest(
        detail: "setting '\(Self.configurationKey)' expects a choice of "
          + Self.allCases.map(\.rawValue).joined(separator: ", "))
    }
    guard let size = VoxAltaModelSize(rawValue: raw.lowercased()) else {
      throw HablareError.invalidRequest(
        detail: "setting '\(Self.configurationKey)' must be one of "
          + Self.allCases.map(\.rawValue).joined(separator: ", ") + ", got '\(raw)'")
    }
    self = size
  }

  /// A plugin configuration selecting this size.
  public var configuration: PluginConfiguration {
    PluginConfiguration(settings: [Self.configurationKey: .choice(rawValue)])
  }
}
