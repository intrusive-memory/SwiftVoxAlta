//
//  VoxAltaPlugin.swift
//  SwiftVoxAlta
//
//  VoxAlta as a SwiftHablare 7 plugin (R1): a local, on-device Qwen3-TTS synthesizer.
//  Voices are `.vox` assets (qwen3-tts clone-prompt embeddings) or the nine
//  CustomVoice preset speakers (`.catalog(pluginId: "voxalta", voiceId:)`).
//

import Foundation
@preconcurrency import MLXAudioCore
import SwiftHablare

/// The VoxAlta `HablarePlugin`: on-device Qwen3-TTS synthesis.
///
/// Register the type with a `PluginRegistry` and select the model size through the
/// plugin configuration:
///
/// ```swift
/// await registry.register(VoxAltaPlugin.self)
/// let plugin = try await registry.plugin(
///   id: VoxAltaPlugin.id, configuration: VoxAltaModelSize.small.configuration)
/// ```
///
/// - `PluginConfiguration` key ``VoxAltaModelSize/configurationKey`` (`"model_size"`):
///   `"1.7b"` (default) or `"0.6b"`.
/// - Voices: `.asset(URL)` for a `.vox` carrying an `embeddings/qwen3-tts/<size>/clone-prompt.bin`,
///   or `.catalog(pluginId: "voxalta", voiceId:)` for a preset (``presetVoiceIds``).
/// - Output: headerless 24 kHz mono 16-bit PCM (`AudioFormat.pcm24kMono16`).
///
/// Instances built through `init(context:)` share ``sharedModelManager``, so every plugin
/// instance in a process shares one resident Qwen3-TTS model.
public final class VoxAltaPlugin: HablarePlugin, VoiceListing, @unchecked Sendable {

  // MARK: - Static metadata

  public static let id = "voxalta"
  public static let displayName = "VoxAlta (On-Device)"
  public static let kind = PluginKind.local

  /// Every model VoxAlta can run: the Base (`.vox`) and CustomVoice (preset) models of
  /// each size. Ids: `"1.7b"`, `"1.7b-customvoice"`, `"0.6b"`, `"0.6b-customvoice"`.
  public static var models: [ModelDescriptor] {
    VoxAltaModelSize.allCases.flatMap { [$0.baseModel, $0.customVoiceModel] }
  }

  /// One per-plugin setting: ``VoxAltaModelSize/configurationKey``.
  public static var settingsSchema: SettingsSchema {
    SettingsSchema([VoxAltaModelSize.settingDefinition])
  }

  /// The model manager `init(context:)` uses. One per process, so plugin instances share
  /// model residency (a Qwen3-TTS model is several GB).
  public static let sharedModelManager = VoxAltaModelManager()

  /// Ids of the CustomVoice preset speakers, for `.catalog(pluginId: "voxalta", voiceId:)`.
  public static var presetVoiceIds: [String] { VoxAltaVoiceProvider.presetSpeakers.map(\.id) }

  // MARK: - Instance

  public let context: PluginContext
  /// The model size resolved from `context.configuration`.
  public let modelSize: VoxAltaModelSize
  /// The synthesizer role, with VoxAlta-specific API (telemetry, model size).
  public let voxAltaSynthesizer: VoxAltaSynthesizer
  private let availability: LocalModelAvailability

  /// Builds the plugin from its context, sharing ``sharedModelManager``. Loads no model.
  ///
  /// - Throws: `HablareError.invalidRequest` when `model_size` is not `"1.7b"` or `"0.6b"`.
  public convenience init(context: PluginContext) async throws {
    try self.init(context: context, modelManager: Self.sharedModelManager)
  }

  /// Builds the plugin over a caller-owned model manager (e.g. a host-wide one).
  ///
  /// - Throws: `HablareError.invalidRequest` when `model_size` is not `"1.7b"` or `"0.6b"`.
  public convenience init(
    context: PluginContext,
    modelManager: VoxAltaModelManager,
    generationSettings: GenerationSettings = .default
  ) throws {
    try self.init(
      context: context, modelManager: modelManager, generationSettings: generationSettings,
      availability: LocalModelAvailability())
  }

  /// Test seam: injectable model availability.
  init(
    context: PluginContext,
    modelManager: VoxAltaModelManager,
    generationSettings: GenerationSettings = .default,
    availability: LocalModelAvailability
  ) throws {
    let size = try VoxAltaModelSize(configuration: context.configuration)
    self.context = context
    self.modelSize = size
    self.availability = availability
    self.voxAltaSynthesizer = VoxAltaSynthesizer(
      modelSize: size, modelManager: modelManager, generationSettings: generationSettings)
  }

  public var synthesizer: (any VoiceSynthesizer)? { voxAltaSynthesizer }

  /// The model ``status()`` requires: the Base model of the configured size. The
  /// CustomVoice model (presets only) is fetched on first preset use and is not required.
  public var requiredModels: [ModelDescriptor] { [modelSize.baseModel] }

  /// `.ready`, or `.needsModel` naming the configured Base model when SwiftAcervo
  /// reports it is not on disk. VoxAlta needs no credentials.
  public func status() async -> PluginStatus {
    let missing = availability.missingModels(requiredModels)
    return missing.isEmpty ? .ready : .needsModel(missing)
  }

  /// The preset speakers, as catalog voices (`providerId` = `"voxalta"`).
  public func voices(languageCode: String) async throws -> [Voice] {
    VoxAltaVoiceProvider.presetSpeakers.map { speaker in
      Voice(
        id: speaker.id, name: speaker.name, description: speaker.description,
        providerId: Self.id, language: languageCode, gender: speaker.gender)
    }
  }

  // MARK: - Telemetry

  /// Attaches or detaches a VoxAlta telemetry reporter (forwarded to the model manager).
  public func setTelemetry(_ reporter: (any VoxAltaTelemetryReporter)?) async {
    await voxAltaSynthesizer.setTelemetry(reporter)
  }

  /// Attaches or detaches an MLXAudio telemetry reporter (forwarded to the model manager).
  public func setMLXTelemetry(_ reporter: (any MLXAudioTelemetryReporter)?) async {
    await voxAltaSynthesizer.setMLXTelemetry(reporter)
  }
}
