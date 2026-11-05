//
//  VoxAltaPluginTests.swift
//  SwiftVoxAltaTests
//
//  VoxAltaPlugin as a SwiftHablare 7 plugin. Nothing here loads an MLX model:
//  conformance runs in `.hardwareFree` mode, model availability is injected, and
//  `.vox` fixtures carry placeholder clone-prompt bytes that are never deserialized.
//

import Foundation
import SwiftHablare
import SwiftHablareTesting
import Testing

@testable import SwiftVoxAlta

// MARK: - Helpers

private enum PluginFixtures {
  static func context(_ configuration: PluginConfiguration = .empty) -> PluginContext {
    PluginContext(
      keys: InMemoryAPIKeyStore(), configuration: configuration,
      registry: PluginRegistry(environment: [:], fallbackKeys: []))
  }

  static func plugin(
    _ configuration: PluginConfiguration = .empty,
    available: Bool = true
  ) throws -> VoxAltaPlugin {
    try VoxAltaPlugin(
      context: context(configuration), modelManager: VoxAltaModelManager(),
      availability: LocalModelAvailability(probe: { _ in available }))
  }

  /// Writes a `.vox` with placeholder qwen3-tts clone prompts for `sizes`.
  static func vox(
    sizes: [VoxAltaModelSize], languages: [String?] = [nil], name: String = "TESTER"
  ) throws -> URL {
    var asset = VoiceAsset(name: name, description: "A test voice used by VoxAltaPluginTests.")
    for size in sizes {
      for language in languages {
        try asset.addEmbedding(
          Data("clone-\(size.slug)-\(language ?? "neutral")".utf8),
          engine: VoxAltaSynthesizer.voxEngine, model: size.baseRepo.rawValue,
          modelSlug: size.slug, language: language, format: "bin")
      }
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("voxalta-plugin-\(UUID().uuidString).vox")
    try asset.write(to: url)
    return url
  }
}

// MARK: - Conformance

@Suite("VoxAltaPlugin - ConformanceKit (hardware-free)", .acervoEnvironment)
struct VoxAltaPluginConformanceTests {

  @Test("ConformanceKit passes in .hardwareFree mode with a preset voice")
  func conformancePreset() async {
    let report = await ConformanceKit.run(
      VoxAltaPlugin.self,
      context: PluginFixtures.context(),
      voice: .catalog(pluginId: VoxAltaPlugin.id, voiceId: "ryan"),
      mode: .hardwareFree)
    #expect(report.passed, "\(report.summary)")
    #expect(report.result(for: .initialization)?.outcome == .passed, "\(report.summary)")
    #expect(report.result(for: .cacheKeyStability)?.outcome == .passed, "\(report.summary)")
  }

  @Test("ConformanceKit passes in .hardwareFree mode with a .vox asset and 0.6b")
  func conformanceAsset() async throws {
    let url = try PluginFixtures.vox(sizes: [.small])
    defer { try? FileManager.default.removeItem(at: url) }
    let report = await ConformanceKit.run(
      VoxAltaPlugin.self,
      context: PluginFixtures.context(VoxAltaModelSize.small.configuration),
      voice: .asset(url),
      mode: .hardwareFree)
    #expect(report.passed, "\(report.summary)")
    #expect(report.result(for: .initialization)?.outcome == .passed, "\(report.summary)")
  }
}

// MARK: - Metadata

@Suite("VoxAltaPlugin - Metadata", .acervoEnvironment)
struct VoxAltaPluginMetadataTests {

  @Test("Static metadata")
  func staticMetadata() {
    #expect(VoxAltaPlugin.id == "voxalta")
    #expect(VoxAltaPlugin.kind == .local)
    #expect(VoxAltaPlugin.credentials.isEmpty)
    #expect(VoxAltaPlugin.models.map(\.id) == ["1.7b", "1.7b-customvoice", "0.6b", "0.6b-customvoice"])
    #expect(VoxAltaPlugin.models.allSatisfy { $0.kind == .local && $0.acervoModelId != nil })
    #expect(VoxAltaPlugin.presetVoiceIds.contains("ryan"))
    #expect(VoxAltaPlugin.presetVoiceIds.count == 9)
  }

  @Test("Synthesizer capabilities, formats and concurrency")
  func synthesizerMetadata() throws {
    let plugin = try PluginFixtures.plugin()
    let synth = try #require(plugin.synthesizer)
    #expect(synth.capabilities.contains(.instruct))
    #expect(!synth.capabilities.contains(.seed))
    #expect(synth.nativeFormats == [.pcm24kMono16])
    #expect(synth.maxConcurrentRequests == 1)
    #expect(plugin.designer == nil)
    let request = SpeechRequest(
      text: "Hello.", voice: .catalog(pluginId: "voxalta", voiceId: "ryan"), seed: 1)
    #expect(synth.cacheKey(for: request) == nil)
  }

  @Test("Preset voices are listed as voxalta catalog voices")
  func listsPresets() async throws {
    let voices = try await PluginFixtures.plugin().voices(languageCode: "en")
    #expect(voices.count == 9)
    #expect(voices.allSatisfy { $0.providerId == "voxalta" })
  }

  @Test("Registry resolves the plugin by id with the default configuration")
  func registryResolves() async throws {
    let registry = PluginRegistry(
      userDefaults: UserDefaults(suiteName: "voxalta-plugin-tests-\(UUID().uuidString)")!,
      environment: [:], fallbackKeys: [], plugins: [VoxAltaPlugin.self])
    let plugin = try await registry.plugin(id: "voxalta")
    let voxAlta = try #require(plugin as? VoxAltaPlugin)
    #expect(voxAlta.modelSize == .large)

    let small = try await registry.plugin(
      id: "voxalta", configuration: VoxAltaModelSize.small.configuration)
    #expect((small as? VoxAltaPlugin)?.modelSize == .small)

    await #expect(throws: HablareError.self) {
      _ = try await registry.plugin(
        id: "voxalta", configuration: PluginConfiguration(settings: ["model_size": .choice("3b")]))
    }
  }
}

// MARK: - Configuration -> model mapping

@Suite("VoxAltaPlugin - Model size configuration", .acervoEnvironment)
struct VoxAltaModelSizeConfigurationTests {

  @Test("Empty configuration defaults to 1.7b")
  func defaultSize() throws {
    let size = try VoxAltaModelSize(configuration: .empty)
    #expect(size == .large)
    #expect(size.baseRepo == .base1_7B)
    #expect(size.customVoiceRepo == .customVoice1_7B)
    #expect(try PluginFixtures.plugin().modelSize == .large)
  }

  @Test("0.6b maps to the 0.6B Base and CustomVoice repos")
  func smallSize() throws {
    let size = try VoxAltaModelSize(
      configuration: PluginConfiguration(settings: ["model_size": .choice("0.6b")]))
    #expect(size == .small)
    #expect(size.baseRepo == .base0_6B)
    #expect(size.customVoiceRepo == .customVoice0_6B)
    let plugin = try PluginFixtures.plugin(VoxAltaModelSize.small.configuration)
    #expect(plugin.voxAltaSynthesizer.modelSize == .small)
  }

  @Test("String values and upper case are accepted")
  func stringValue() throws {
    let size = try VoxAltaModelSize(
      configuration: PluginConfiguration(settings: ["model_size": .string("1.7B")]))
    #expect(size == .large)
  }

  @Test("Unknown sizes and wrong types throw HablareError.invalidRequest")
  func invalidSizes() {
    #expect(throws: HablareError.self) {
      _ = try VoxAltaModelSize(
        configuration: PluginConfiguration(settings: ["model_size": .choice("7b")]))
    }
    #expect(throws: HablareError.self) {
      _ = try VoxAltaModelSize(
        configuration: PluginConfiguration(settings: ["model_size": .int(1)]))
    }
    #expect(throws: HablareError.self) {
      _ = try PluginFixtures.plugin(PluginConfiguration(settings: ["model_size": .choice("7b")]))
    }
  }

  @Test("Settings schema declares model_size as a per-plugin choice defaulting to 1.7b")
  func schema() throws {
    let validated = try PluginConfiguration.empty.validated(against: VoxAltaPlugin.settingsSchema)
    #expect(validated.settings["model_size"] == .choice("1.7b"))
    #expect(throws: HablareError.self) {
      _ = try PluginConfiguration(settings: ["model_size": .choice("2b")])
        .validated(against: VoxAltaPlugin.settingsSchema)
    }
  }

  @Test("Model descriptors carry the Acervo repo ids")
  func descriptors() {
    #expect(VoxAltaModelSize.large.baseModel.acervoModelId == Qwen3TTSModelRepo.base1_7B.rawValue)
    #expect(VoxAltaModelSize.small.baseModel.acervoModelId == Qwen3TTSModelRepo.base0_6B.rawValue)
    #expect(
      VoxAltaModelSize.small.customVoiceModel.acervoModelId
        == Qwen3TTSModelRepo.customVoice0_6B.rawValue)
  }

  @Test("status() reports .needsModel for the configured Base model when missing")
  func statusNeedsModel() async throws {
    let missing = try PluginFixtures.plugin(VoxAltaModelSize.small.configuration, available: false)
    #expect(await missing.status() == .needsModel([VoxAltaModelSize.small.baseModel]))

    let missingLarge = try PluginFixtures.plugin(available: false)
    #expect(await missingLarge.status() == .needsModel([VoxAltaModelSize.large.baseModel]))

    let present = try PluginFixtures.plugin(available: true)
    #expect(await present.status() == .ready)
  }
}

// MARK: - .asset vs .catalog

@Suite("VoxAltaPlugin - Voice references", .acervoEnvironment)
struct VoxAltaPluginVoiceReferenceTests {

  @Test("Catalog presets are ready; other catalogs are unsupported")
  func catalogReadiness() async throws {
    let synth = try #require(try PluginFixtures.plugin().synthesizer)
    #expect(await synth.readiness(for: .catalog(pluginId: "voxalta", voiceId: "ryan")) == .ready(source: nil))
    if case .unsupported = await synth.readiness(for: .catalog(pluginId: "apple", voiceId: "ryan")) {
    } else {
      Issue.record("another plugin's catalog voice must be unsupported")
    }
    if case .unsupported = await synth.readiness(for: .catalog(pluginId: "voxalta", voiceId: "nobody")) {
    } else {
      Issue.record("an unknown preset must be unsupported")
    }
  }

  @Test(".vox asset needs preparation, is ready after prepare, and resets on release")
  func assetLifecycle() async throws {
    let url = try PluginFixtures.vox(sizes: [.large, .small])
    defer { try? FileManager.default.removeItem(at: url) }
    let synth = try #require(try PluginFixtures.plugin().synthesizer)
    let voice = VoiceReference.asset(url)

    guard case .needsPreparation(let source?) = await synth.readiness(for: voice) else {
      Issue.record("expected .needsPreparation with a source")
      return
    }
    #expect(source.engine == "qwen3-tts")
    #expect(source.kind == .embedding)
    #expect(source.model == "1.7b")

    try await synth.prepare(voice)
    #expect(await synth.readiness(for: voice) == .ready(source: source))

    await synth.release(voice)
    #expect(await synth.readiness(for: voice) == .needsPreparation(source: source))
  }

  @Test("The configured size selects the matching clone prompt")
  func assetSizeSelection() async throws {
    let url = try PluginFixtures.vox(sizes: [.large, .small])
    defer { try? FileManager.default.removeItem(at: url) }
    let synth = try #require(
      try PluginFixtures.plugin(VoxAltaModelSize.small.configuration).synthesizer)
    #expect(await synth.readiness(for: .asset(url)).source?.model == "0.6b")
  }

  @Test("A .vox without a clone prompt for the configured size is unsupported")
  func assetMissingSize() async throws {
    let url = try PluginFixtures.vox(sizes: [.small])
    defer { try? FileManager.default.removeItem(at: url) }
    let synth = try #require(try PluginFixtures.plugin().synthesizer)
    if case .unsupported = await synth.readiness(for: .asset(url)) {
    } else {
      Issue.record("1.7b plugin must not accept a 0.6b-only .vox")
    }
    await #expect(throws: HablareError.self) { try await synth.prepare(.asset(url)) }
    await #expect(throws: HablareError.self) {
      _ = try await synth.synthesize(SpeechRequest(text: "Hello.", voice: .asset(url)))
    }
  }

  @Test("An unreadable file is unsupported")
  func assetUnreadable() async throws {
    let synth = try #require(try PluginFixtures.plugin().synthesizer)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).vox")
    if case .unsupported = await synth.readiness(for: .asset(url)) {
    } else {
      Issue.record("a missing file must be unsupported")
    }
  }

  @Test("Language-keyed clone prompts prefer exact, then base language, then neutral")
  func languageSelection() throws {
    let url = try PluginFixtures.vox(sizes: [.large], languages: [nil, "es", "fr-FR"])
    defer { try? FileManager.default.removeItem(at: url) }
    let asset = try VoiceAsset(contentsOf: url)
    func path(_ language: String?) -> String? {
      VoxAltaSynthesizer.cloneSource(in: asset, size: .large, language: language)?.path
    }
    #expect(path(nil) == "embeddings/qwen3-tts/1.7b/clone-prompt.bin")
    #expect(path("es") == "embeddings/qwen3-tts/1.7b/es/clone-prompt.bin")
    #expect(path("es-MX") == "embeddings/qwen3-tts/1.7b/es/clone-prompt.bin")
    #expect(path("fr-FR") == "embeddings/qwen3-tts/1.7b/fr-FR/clone-prompt.bin")
    #expect(path("de") == "embeddings/qwen3-tts/1.7b/clone-prompt.bin")
  }

  @Test("Bad requests throw categorised HablareErrors without loading a model")
  func badRequests() async throws {
    let synth = try #require(try PluginFixtures.plugin().synthesizer)
    await #expect(throws: HablareError.self) {
      _ = try await synth.synthesize(
        SpeechRequest(text: "  ", voice: .catalog(pluginId: "voxalta", voiceId: "ryan")))
    }
    await #expect(throws: HablareError.self) {
      _ = try await synth.synthesize(
        SpeechRequest(text: "Hello.", voice: .catalog(pluginId: "other", voiceId: "ryan")))
    }
    await #expect(throws: HablareError.self) {
      _ = try await synth.synthesize(
        SpeechRequest(text: "Hello.", voice: .catalog(pluginId: "voxalta", voiceId: "nobody")))
    }
  }
}

// MARK: - Audio and error mapping

@Suite("VoxAltaPlugin - Audio and errors", .acervoEnvironment)
struct VoxAltaPluginAudioTests {

  @Test("WAV output is stripped to headerless 24 kHz mono 16-bit PCM")
  func pcmPayload() throws {
    let samples = [Int16](repeating: 7, count: 24_000)
    let wav = AudioConversion.buildWAVData(pcmSamples: samples, sampleRate: 24_000)
    let pcm = try #require(VoxAltaSynthesizer.pcmPayload(ofWAV: wav))
    #expect(pcm.format == .pcm24kMono16)
    #expect(pcm.data.count == 48_000)
    #expect(pcm.data.prefix(4) != Data("RIFF".utf8))
    #expect(VoxAltaSynthesizer.pcmPayload(ofWAV: Data([1, 2, 3])) == nil)
  }

  @Test("Engine errors map to categorised HablareErrors")
  func errorMapping() {
    let voice = VoiceReference.catalog(pluginId: "voxalta", voiceId: "ryan")
    let model = VoxAltaModelSize.large.customVoiceModel
    func map(_ error: any Error) -> HablareError {
      VoxAltaSynthesizer.hablareError(error, voice: voice, model: model)
    }
    #expect(map(VoxAltaError.modelNotAvailable("x")).category == .permanentUntilDownloaded)
    #expect(map(VoxAltaError.unsupportedLanguage("tlh")).category == .permanent)
    #expect(map(VoxAltaError.voiceNotLoaded("x")).category == .permanent)
    #expect(map(VoxAltaError.cloningFailed("x")).category == .transient)
    #expect(map(CancellationError()).category == .cancelled)
  }
}
