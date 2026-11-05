//
//  VoxAltaSynthesizer.swift
//  SwiftVoxAlta
//
//  The `VoiceSynthesizer` role of `VoxAltaPlugin`. Drives `VoxAltaVoiceProvider`
//  (the VoxAlta engine) and reports headerless 24 kHz mono 16-bit PCM.
//

import Foundation
@preconcurrency import MLXAudioCore
import SwiftHablare

/// VoxAlta's Hablare synthesizer.
///
/// - `.asset(URL)`: a `.vox` file; the `qwen3-tts` clone prompt for the configured model
///   size is read through Hablare's `VoiceAsset` (core is the `.vox` reader).
///   `prepare(_:)` loads it into the voice cache; `release(_:)` drops it.
/// - `.catalog(pluginId: "voxalta", voiceId:)`: a CustomVoice preset speaker.
///
/// Capabilities: `.instruct` (forwarded to Qwen3-TTS on both paths) and `.onDevice`.
/// No `.seed`: Qwen3-TTS sampling is not reproducible from a seed, so ``cacheKey(for:)``
/// is `nil` (R8).
public final class VoxAltaSynthesizer: VoiceSynthesizer, @unchecked Sendable {

  /// The `.vox` engine namespace VoxAlta reads (`embeddings/qwen3-tts/...`).
  public static let voxEngine = "qwen3-tts"

  static let supportedCapabilities: SynthesisCapabilities = [.instruct, .onDevice]

  public let modelSize: VoxAltaModelSize
  public var capabilities: SynthesisCapabilities { Self.supportedCapabilities }
  /// VoxAlta chunks long text at sentence boundaries itself.
  public var limits: SynthesisLimits { .unlimited }
  public var nativeFormats: [AudioFormat] { [.pcm24kMono16] }
  /// One GPU generation at a time.
  public var maxConcurrentRequests: Int { 1 }
  public var consumedSources: [VoiceSourcePattern] {
    [VoiceSourcePattern(engine: Self.voxEngine, kind: .embedding)]
  }

  private let engine: VoxAltaVoiceProvider
  private let prepared = PreparedVoices()

  init(
    modelSize: VoxAltaModelSize,
    modelManager: VoxAltaModelManager,
    generationSettings: GenerationSettings
  ) {
    self.modelSize = modelSize
    self.engine = VoxAltaVoiceProvider(
      modelManager: modelManager,
      baseModelRepo: modelSize.baseRepo,
      customVoiceModelRepo: modelSize.customVoiceRepo,
      generationSettings: generationSettings)
  }

  // MARK: - Readiness and residency

  public func readiness(for voice: VoiceReference) async -> VoiceReadiness {
    switch voice {
    case .catalog(let pluginId, let voiceId):
      guard pluginId == VoxAltaPlugin.id else {
        return .unsupported(reason: "not a '\(VoxAltaPlugin.id)' catalog voice")
      }
      guard Self.isPreset(voiceId) else {
        return .unsupported(reason: "'\(voiceId)' is not a VoxAlta preset speaker")
      }
      return .ready(source: nil)
    case .asset(let url):
      let selection: (asset: VoiceAsset, source: VoiceSource)
      do {
        selection = try selectSource(at: url, language: nil, voice: voice)
      } catch let error as HablareError {
        if case .unsupportedVoice(_, let reason) = error { return .unsupported(reason: reason) }
        return .unsupported(reason: "cannot read \(url.lastPathComponent)")
      } catch {
        return .unsupported(reason: "cannot read \(url.lastPathComponent)")
      }
      let key = Self.cacheId(url: url, source: selection.source)
      return prepared.contains(key)
        ? .ready(source: selection.source) : .needsPreparation(source: selection.source)
    }
  }

  /// Loads the `.vox` clone prompt into the voice cache. A no-op for preset speakers
  /// (their model loads on first synthesis).
  public func prepare(_ voice: VoiceReference) async throws {
    guard case .asset(let url) = voice else {
      if case .unsupported(let reason) = await readiness(for: voice) {
        throw HablareError.unsupportedVoice(voice, reason: reason)
      }
      return
    }
    let selection = try selectSource(at: url, language: nil, voice: voice)
    _ = try await load(selection.source, from: selection.asset, url: url, voice: voice)
  }

  public func release(_ voice: VoiceReference) async {
    guard case .asset(let url) = voice else { return }
    for key in prepared.removeAll(forURL: Self.urlKey(url)) {
      await engine.unloadVoice(id: key)
    }
  }

  // MARK: - Synthesis

  public func synthesize(_ request: SpeechRequest) async throws -> GeneratedAudio {
    if Task.isCancelled { throw HablareError.cancelled }
    guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw HablareError.invalidRequest(detail: "text cannot be empty")
    }
    let languageCode = request.languageCode ?? "en"
    do {
      _ = try TTSLanguage(languageCode: languageCode)
    } catch {
      throw HablareError.invalidRequest(
        detail: "VoxAlta cannot speak language '\(languageCode)'")
    }

    let engineVoiceId: String
    let model: ModelDescriptor
    let sourceUsed: VoiceSource?
    switch request.voice {
    case .catalog(let pluginId, let voiceId):
      guard pluginId == VoxAltaPlugin.id, Self.isPreset(voiceId) else {
        throw HablareError.unsupportedVoice(
          request.voice, reason: "not a VoxAlta preset speaker ('\(pluginId)'/'\(voiceId)')")
      }
      engineVoiceId = voiceId
      model = modelSize.customVoiceModel
      sourceUsed = nil
    case .asset(let url):
      let selection = try selectSource(
        at: url, language: request.languageCode, voice: request.voice)
      engineVoiceId = try await load(
        selection.source, from: selection.asset, url: url, voice: request.voice)
      model = modelSize.baseModel
      sourceUsed = selection.source
    }

    if Task.isCancelled { throw HablareError.cancelled }
    let wav: Data
    do {
      wav = try await engine.generateAudio(
        context: GenerationContext(phrase: request.text, instruct: request.instruct),
        voiceId: engineVoiceId,
        languageCode: languageCode)
    } catch {
      throw Self.hablareError(error, voice: request.voice, model: model)
    }
    if Task.isCancelled { throw HablareError.cancelled }

    guard let pcm = Self.pcmPayload(ofWAV: wav) else {
      throw HablareError.transient(
        underlying: VoxAltaError.audioExportFailed("engine returned unreadable WAV data"))
    }
    let bytesPerSecond = Double(pcm.format.sampleRate * pcm.format.channels * 2)
    return GeneratedAudio(
      data: pcm.data,
      format: pcm.format,
      duration: Double(pcm.data.count) / bytesPerSecond,
      droppedInstruct: request.instruct != nil && !capabilities.contains(.instruct),
      sourceUsed: sourceUsed)
  }

  // MARK: - Telemetry

  func setTelemetry(_ reporter: (any VoxAltaTelemetryReporter)?) async {
    await engine.setTelemetry(reporter)
  }

  func setMLXTelemetry(_ reporter: (any MLXAudioTelemetryReporter)?) async {
    await engine.setMLXTelemetry(reporter)
  }

  // MARK: - .vox source selection

  /// Opens `url` and picks the clone-prompt source for the configured size.
  private func selectSource(
    at url: URL, language: String?, voice: VoiceReference
  ) throws -> (asset: VoiceAsset, source: VoiceSource) {
    let asset = try VoiceAsset(contentsOf: url)
    guard let source = Self.cloneSource(in: asset, size: modelSize, language: language) else {
      throw HablareError.unsupportedVoice(
        voice,
        reason:
          "\(url.lastPathComponent) has no \(Self.voxEngine) \(modelSize.slug) clone prompt")
    }
    return (asset, source)
  }

  /// Reads the source's clone prompt into the engine's voice cache (once) and returns the
  /// engine voice id it is cached under.
  private func load(
    _ source: VoiceSource, from asset: VoiceAsset, url: URL, voice: VoiceReference
  ) async throws -> String {
    let key = Self.cacheId(url: url, source: source)
    if prepared.contains(key) { return key }
    guard let path = source.path, let data = asset.entryData(at: path), !data.isEmpty else {
      throw HablareError.unsupportedVoice(
        voice, reason: "\(url.lastPathComponent) clone prompt entry is empty")
    }
    await engine.loadVoice(id: key, clonePromptData: data)
    prepared.insert(key, forURL: Self.urlKey(url))
    return key
  }

  /// The qwen3-tts clone-prompt embedding for `size`, preferring an exact language match,
  /// then the base language, then the language-neutral entry.
  static func cloneSource(
    in asset: VoiceAsset, size: VoxAltaModelSize, language: String?
  ) -> VoiceSource? {
    let candidates = asset.sources.filter { source in
      guard source.engine == voxEngine, source.kind == .embedding,
        let path = source.path, path.hasSuffix("clone-prompt.bin")
      else { return false }
      return modelMatches(source.model, size: size)
    }
    func languageOf(_ source: VoiceSource) -> String? {
      let parts = (source.path ?? "").split(separator: "/").map(String.init)
      return parts.count >= 5 ? parts[3].lowercased() : nil
    }
    if let language, !language.isEmpty {
      let tag = language.lowercased()
      let base = tag.split(separator: "-").first.map(String.init) ?? tag
      if let exact = candidates.first(where: { languageOf($0) == tag }) { return exact }
      if let baseMatch = candidates.first(where: { languageOf($0) == base }) {
        return baseMatch
      }
    }
    return candidates.first(where: { languageOf($0) == nil }) ?? candidates.first
  }

  /// True when a `.vox` source model names `size`: the slug folder (`"1.7b"`), the full
  /// repo id, or any model string containing the slug.
  static func modelMatches(_ model: String?, size: VoxAltaModelSize) -> Bool {
    guard let model = model?.lowercased(), !model.isEmpty else { return false }
    if let repo = Qwen3TTSModelRepo(rawValue: model) { return repo.slug == size.slug }
    if let repo = Qwen3TTSModelRepo.allCases.first(where: { $0.rawValue.lowercased() == model }) {
      return repo.slug == size.slug
    }
    return model == size.slug || model.contains(size.slug)
  }

  static func isPreset(_ voiceId: String) -> Bool {
    VoxAltaVoiceProvider.presetSpeakers.contains { $0.id == voiceId }
  }

  static func urlKey(_ url: URL) -> String { url.standardizedFileURL.path }

  static func cacheId(url: URL, source: VoiceSource) -> String {
    "vox:\(urlKey(url))#\(source.path ?? "")"
  }

  // MARK: - Audio

  /// Strips the RIFF header from 16-bit PCM WAV data. Returns the raw samples and their
  /// format, or `nil` when the bytes are not 16-bit PCM WAV.
  static func pcmPayload(ofWAV data: Data) -> (data: Data, format: AudioFormat)? {
    let bytes = [UInt8](data)
    guard bytes.count >= 12, bytes[0..<4].elementsEqual("RIFF".utf8),
      bytes[8..<12].elementsEqual("WAVE".utf8)
    else { return nil }
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
    var offset = 12
    var fmt: (rate: Int, channels: Int, bits: Int)?
    while offset + 8 <= bytes.count {
      let size = u32(offset + 4)
      let body = offset + 8
      if bytes[offset..<offset + 4].elementsEqual("fmt ".utf8) {
        guard size >= 16, body + 16 <= bytes.count else { return nil }
        fmt = (u32(body + 4), u16(body + 2), u16(body + 14))
      } else if bytes[offset..<offset + 4].elementsEqual("data".utf8) {
        guard let fmt, fmt.bits == 16, fmt.channels > 0, fmt.rate > 0 else { return nil }
        let end = min(bytes.count, body + size)
        let format =
          (fmt.rate == 24_000 && fmt.channels == 1)
          ? AudioFormat.pcm24kMono16
          : AudioFormat(container: .pcm, sampleRate: fmt.rate, channels: fmt.channels, bitDepth: 16)
        return (Data(bytes[body..<end]), format)
      }
      offset = body + size + (size & 1)
    }
    return nil
  }

  // MARK: - Errors

  /// Maps engine errors onto `HablareError` so every failure carries a category (R10).
  static func hablareError(
    _ error: any Error, voice: VoiceReference, model: ModelDescriptor
  ) -> HablareError {
    if let error = error as? HablareError { return error }
    if error is CancellationError { return .cancelled }
    guard let error = error as? VoxAltaError else { return .transient(underlying: error) }
    switch error {
    case .modelNotAvailable:
      return .modelNotAvailable(model)
    case .voiceNotLoaded(let id):
      return .unsupportedVoice(voice, reason: "voice '\(id)' is not loaded")
    case .unsupportedLanguage(let tag):
      return .invalidRequest(detail: "VoxAlta cannot speak language '\(tag)'")
    case .voxImportFailed(let detail):
      return .invalidRequest(detail: "cannot read .vox: \(detail)")
    case .cloningFailed, .insufficientMemory, .audioExportFailed, .voxExportFailed:
      return .transient(underlying: error)
    }
  }
}

// MARK: - Prepared-voice bookkeeping

/// Lock-guarded map of `.vox` URL → engine voice ids loaded for it.
private final class PreparedVoices: @unchecked Sendable {
  private let lock = NSLock()
  private var byURL: [String: Set<String>] = [:]

  func contains(_ key: String) -> Bool {
    lock.withLock { byURL.values.contains { $0.contains(key) } }
  }

  func insert(_ key: String, forURL url: String) {
    lock.withLock { _ = byURL[url, default: []].insert(key) }
  }

  func removeAll(forURL url: String) -> Set<String> {
    lock.withLock { byURL.removeValue(forKey: url) ?? [] }
  }
}
