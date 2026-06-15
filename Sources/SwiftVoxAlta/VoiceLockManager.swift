//
//  VoiceLockManager.swift
//  SwiftVoxAlta
//
//  Creates and uses VoiceLocks for consistent voice identity across TTS generations.
//

import Foundation
@preconcurrency import MLX
@preconcurrency import MLXAudioTTS
@preconcurrency import MLXLMCommon
import Tuberia

/// Internal logger for VoiceLockManager clone prompt caching.
/// Writes to stderr to match the project-wide logging convention.
private enum VoiceLockManagerLogger {
  static func log(_ message: String) {
    FileHandle.standardError.write(Data("[VoiceLockManager] \(message)\n".utf8))
  }
}

/// Manages creation and use of `VoiceLock` instances for voice cloning.
///
/// `VoiceLockManager` is an enum namespace with static methods. It handles:
/// - Creating a `VoiceLock` from candidate audio (voice design output)
/// - Generating audio from a locked voice identity
///
/// Voice locking extracts a clone prompt (speaker embedding + reference codes) from
/// the selected voice candidate, serializes it, and stores it in a `VoiceLock`.
/// Subsequent audio generation uses the deserialized clone prompt for consistent
/// voice reproduction.
public enum VoiceLockManager: Sendable {

  /// Default reference text for clone prompt extraction when no custom sentence is provided.
  static let defaultReferenceSampleText = "Hello, this is a voice sample for testing purposes."

  // MARK: - Lock Creation

  /// Create a VoiceLock from candidate audio by extracting a voice clone prompt.
  ///
  /// Loads a Base model (which supports voice cloning), converts the candidate
  /// WAV audio to an MLXArray, and uses the model's speaker encoder to extract
  /// a reusable clone prompt. The clone prompt is serialized and stored in the
  /// returned `VoiceLock`.
  ///
  /// - Parameters:
  ///   - characterName: The character name to associate with this voice lock.
  ///   - candidateAudio: WAV format Data of the selected voice candidate.
  ///   - designInstruction: The voice description text used to generate the candidate.
  ///   - modelManager: The model manager used to load the Base model.
  ///   - sampleSentence: The text that was spoken in the candidate audio. If nil,
  ///     falls back to the default reference text.
  ///   - modelRepo: The Base model variant to use for cloning. Defaults to `.base1_7B`.
  ///   - language: The ``TTSLanguage`` of the reference audio / `sampleSentence`. Forwarded
  ///     to the speaker encoder (as `language.modelName`) so the tokenizer aligns the
  ///     reference text against the reference audio. Defaults to `.english`. The caller
  ///     (echada) is responsible for supplying a `sampleSentence` in the same language;
  ///     `createLock` does not translate.
  /// - Returns: A `VoiceLock` containing the serialized clone prompt.
  /// - Throws: `VoxAltaError.cloningFailed` if clone prompt extraction fails,
  ///           `VoxAltaError.modelNotAvailable` if the Base model cannot be loaded.
  public static func createLock(
    characterName: String,
    candidateAudio: Data,
    designInstruction: String,
    modelManager: VoxAltaModelManager,
    sampleSentence: String? = nil,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    language: TTSLanguage = .english
  ) async throws -> VoiceLock {
    // Load Base model (supports voice cloning)
    let model = try await modelManager.loadModel(modelRepo)

    // Cast to Qwen3TTSModel for clone prompt API
    guard let qwenModel = model as? Qwen3TTSModel else {
      throw VoxAltaError.cloningFailed(
        "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
      )
    }

    // Convert WAV Data to MLXArray
    let refAudio: MLXArray
    do {
      refAudio = try AudioConversion.wavDataToMLXArray(candidateAudio)
    } catch {
      throw VoxAltaError.cloningFailed(
        "Failed to parse candidate WAV audio: \(error.localizedDescription)"
      )
    }

    // Create voice clone prompt
    language.logConsumption(stage: "voicelock.createLock", detail: characterName)
    let clonePrompt: VoiceClonePrompt
    do {
      clonePrompt = try qwenModel.createVoiceClonePrompt(
        refAudio: refAudio,
        refText: sampleSentence ?? defaultReferenceSampleText,
        language: language.modelName
      )
    } catch {
      throw VoxAltaError.cloningFailed(
        "Failed to create voice clone prompt for '\(characterName)': \(error.localizedDescription)"
      )
    }

    // Flush GPU state after speaker encoder pass.
    // Without this, loading a new model can crash in AGX::ComputeContext
    // due to stale Metal command buffers from the previous model.
    await MemoryManager.shared.clearGPUCache()

    // Serialize clone prompt to Data
    let clonePromptData: Data
    do {
      clonePromptData = try clonePrompt.serialize()
    } catch {
      throw VoxAltaError.cloningFailed(
        "Failed to serialize voice clone prompt: \(error.localizedDescription)"
      )
    }

    return VoiceLock(
      characterName: characterName,
      clonePromptData: clonePromptData,
      designInstruction: designInstruction,
      lockedAt: Date()
    )
  }

  // MARK: - Audio Generation from Lock (Context Envelope)

  /// Generate speech audio using a locked voice identity and a generation context.
  ///
  /// Logs the envelope size, extracts the `instruct` hint from metadata (if present),
  /// and delegates to the text-based `generateAudio`. The instruct hint is forwarded
  /// to Qwen3-TTS as a performance direction (e.g., "Speak softly, sotto voce").
  ///
  /// - Parameters:
  ///   - context: The generation context containing the phrase and optional metadata.
  ///   - voiceLock: The voice lock containing the serialized clone prompt.
  ///   - language: The ``TTSLanguage`` for generation. Required — there is no default.
  ///   - modelManager: The model manager used to load the Base model.
  ///   - modelRepo: The Base model variant to use for generation. Defaults to `.base1_7B`.
  ///   - cache: Optional voice cache for clone prompt caching.
  ///   - settings: Generation parameters controlling sampling behavior.
  /// - Returns: WAV format Data of the generated speech audio (24kHz, 16-bit PCM, mono).
  /// - Throws: `VoxAltaError.cloningFailed` if generation fails,
  ///           `VoxAltaError.modelNotAvailable` if the Base model cannot be loaded.
  public static func generateAudio(
    context: GenerationContext,
    voiceLock: VoiceLock,
    language: TTSLanguage,
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    cache: VoxAltaVoiceCache? = nil,
    settings: GenerationSettings = .default
  ) async throws -> Data {
    VoiceLockManagerLogger.log(
      "Envelope for '\(voiceLock.characterName)': \(context.serializedSize) bytes, \(context.metadata.count) metadata key(s)"
    )
    if let instruct = context.instruct {
      VoiceLockManagerLogger.log("Instruct hint for '\(voiceLock.characterName)': \(instruct)")
    }
    return try await generateAudio(
      text: context.phrase,
      voiceLock: voiceLock,
      language: language,
      instruct: context.instruct,
      modelManager: modelManager,
      modelRepo: modelRepo,
      cache: cache,
      settings: settings
    )
  }

  // MARK: - Audio Generation from Lock (Text)

  /// Generate speech audio using a locked voice identity.
  ///
  /// Deserializes the clone prompt from the voice lock and uses it to generate
  /// audio with a Base model. The resulting audio reproduces the locked voice
  /// identity consistently across calls.
  ///
  /// If a cache is provided, the clone prompt is retrieved from the cache if available
  /// (avoiding deserialization overhead). On cache miss, the clone prompt is deserialized
  /// and stored in the cache for subsequent calls.
  ///
  /// - Parameters:
  ///   - text: The text to synthesize.
  ///   - voiceLock: The voice lock containing the serialized clone prompt.
  ///   - language: The ``TTSLanguage`` for generation. Required — there is no default.
  ///   - instruct: Optional performance direction for the TTS model (e.g., "Speak softly").
  ///     Forwarded to Qwen3-TTS as the `instruct` parameter to influence vocal delivery.
  ///   - modelManager: The model manager used to load the Base model.
  ///   - modelRepo: The Base model variant to use for generation. Defaults to `.base1_7B`.
  ///   - cache: Optional voice cache for clone prompt caching. If provided, reduces
  ///            deserialization overhead on repeated calls.
  ///   - settings: Generation parameters controlling sampling behavior.
  /// - Returns: WAV format Data of the generated speech audio (24kHz, 16-bit PCM, mono).
  /// - Throws: `VoxAltaError.cloningFailed` if generation fails,
  ///           `VoxAltaError.modelNotAvailable` if the Base model cannot be loaded.
  public static func generateAudio(
    text: String,
    voiceLock: VoiceLock,
    language: TTSLanguage,
    instruct: String? = nil,
    modelManager: VoxAltaModelManager,
    modelRepo: Qwen3TTSModelRepo = .base1_7B,
    cache: VoxAltaVoiceCache? = nil,
    settings: GenerationSettings = .default
  ) async throws -> Data {
    // Load Base model
    let model = try await modelManager.loadModel(modelRepo)

    // Cast to Qwen3TTSModel
    guard let qwenModel = model as? Qwen3TTSModel else {
      throw VoxAltaError.cloningFailed(
        "Loaded model is not a Qwen3TTSModel. Got \(type(of: model))."
      )
    }

    // Check cache for deserialized clone prompt first
    let clonePrompt: VoiceClonePrompt
    let dataHash = voiceLock.clonePromptData.prefix(16).map { String(format: "%02x", $0) }.joined()
    VoiceLockManagerLogger.log(
      "🔍 Generating for '\(voiceLock.characterName)' (data hash: \(dataHash), size: \(voiceLock.clonePromptData.count) bytes)"
    )

    if let cache = cache, let cached = await cache.getClonePrompt(id: voiceLock.characterName) {
      clonePrompt = cached
      VoiceLockManagerLogger.log(
        "✅ Clone prompt cache HIT for '\(voiceLock.characterName)' - reusing deserialized clone prompt"
      )
    } else {
      // Cache miss - deserialize clone prompt
      do {
        clonePrompt = try VoiceClonePrompt.deserialize(from: voiceLock.clonePromptData)
        VoiceLockManagerLogger.log(
          "⚠️  Clone prompt cache MISS for '\(voiceLock.characterName)' - deserializing now")
      } catch {
        throw VoxAltaError.cloningFailed(
          "Failed to deserialize voice clone prompt for '\(voiceLock.characterName)': \(error.localizedDescription)"
        )
      }

      // Store in cache for next time
      if let cache = cache {
        await cache.storeClonePrompt(id: voiceLock.characterName, clonePrompt: clonePrompt)
        VoiceLockManagerLogger.log(
          "💾 Stored clone prompt in cache for '\(voiceLock.characterName)'")
      }
    }

    // Log generation parameters
    VoiceLockManagerLogger.log(
      "🎛️  Generation params: temp=\(settings.temperature), topP=\(settings.topP), repPenalty=\(settings.repetitionPenalty), maxTokens=\(settings.maxTokens)"
    )
    if let instruct = instruct {
      VoiceLockManagerLogger.log("📝 Instruct: \"\(instruct)\"")
    }
    language.logConsumption(stage: "voicelock.generate", detail: voiceLock.characterName)
    VoiceLockManagerLogger.log(
      "🗣️  Text (\(text.count) chars): \"\(text.prefix(100))\(text.count > 100 ? "..." : "")\"")

    // Auto-chunk long phrases at sentence boundaries to defeat ICL anchor dilution.
    // See FIXME-sentence-chunking.md and SENTENCE_CHUNKING_DISCUSSION.md for the
    // root-cause analysis (TRIM ratio drift) and design rationale.
    let estimatedDuration = estimateDuration(text: text)
    let shouldChunk =
      settings.enableAutoChunking && estimatedDuration > settings.chunkTargetDuration

    let audioArray: MLXArray
    do {
      if shouldChunk {
        let chunks = splitAtSentences(text: text, maxDuration: settings.chunkTargetDuration)
        VoiceLockManagerLogger.log(
          "✂️  Auto-chunking (\(text.count) chars, ~\(String(format: "%.1f", estimatedDuration))s) into \(chunks.count) chunk(s)"
        )

        let silenceArray = generateSilenceArray(
          duration: settings.chunkPauseDuration,
          sampleRate: qwenModel.sampleRate
        )

        var arrays: [MLXArray] = []
        arrays.reserveCapacity(chunks.count * 2)

        for (i, chunk) in chunks.enumerated() {
          let preview = chunk.prefix(60)
          let suffix = chunk.count > 60 ? "..." : ""
          VoiceLockManagerLogger.log(
            "  ↳ Chunk \(i + 1)/\(chunks.count) (\(chunk.count) chars): \"\(preview)\(suffix)\""
          )

          TTSLanguage.trace("voicelock.→fork", "\(language.modelName) (chunk)")
          let rawChunkArray = try qwenModel.generateWithClonePrompt(
            text: chunk,
            clonePrompt: clonePrompt,
            language: language.modelName,
            instruct: instruct,
            temperature: settings.temperature,
            topP: settings.topP,
            repetitionPenalty: settings.repetitionPenalty,
            maxTokens: settings.maxTokens
          )
          // Flatten to 1-D so all arrays concatenate cleanly along axis 0.
          let flatChunk = rawChunkArray.ndim > 1 ? rawChunkArray.reshaped(-1) : rawChunkArray
          // Materialize before clearing GPU cache so the buffer stays valid for concat.
          eval(flatChunk)
          arrays.append(flatChunk)
          if i < chunks.count - 1 {
            arrays.append(silenceArray)
          }
          // Per-chunk flush: prevents stale Metal buffers from one chunk bleeding
          // into the next, mirroring the inter-call protection below.
          await MemoryManager.shared.clearGPUCache()
        }

        audioArray = MLX.concatenated(arrays, axis: 0)
      } else {
        TTSLanguage.trace("voicelock.→fork", language.modelName)
        audioArray = try qwenModel.generateWithClonePrompt(
          text: text,
          clonePrompt: clonePrompt,
          language: language.modelName,
          instruct: instruct,
          temperature: settings.temperature,
          topP: settings.topP,
          repetitionPenalty: settings.repetitionPenalty,
          maxTokens: settings.maxTokens
        )
      }
    } catch {
      throw VoxAltaError.cloningFailed(
        "Failed to generate audio for '\(voiceLock.characterName)': \(error.localizedDescription)"
      )
    }

    // Flush GPU state so the next generation starts with a clean context.
    // Without this, stale Metal buffers from the KV cache and intermediate
    // activations can bleed into subsequent calls, causing inconsistent quality.
    // AGX crash prevention: clears stale Metal command buffers between generations.
    await MemoryManager.shared.clearGPUCache()

    // Convert to WAV Data
    do {
      return try AudioConversion.mlxArrayToWAVData(audioArray, sampleRate: qwenModel.sampleRate)
    } catch {
      throw VoxAltaError.audioExportFailed(
        "Failed to convert generated audio to WAV: \(error.localizedDescription)"
      )
    }
  }

  // MARK: - Sentence Chunking Helpers

  /// Empirically observed average speaking rate for Qwen3-TTS at default settings.
  /// Calibration source: `podcast-tao-de-jing` chapter 2 element 11
  /// (421 chars → 23.12s → 0.0549 s/char). Accurate to ~10% for English
  /// narrator-style prose.
  public static let estimatedSecondsPerChar: Double = 0.055

  /// Estimate the audio duration of a given text, in seconds.
  ///
  /// Linear heuristic: `chars × estimatedSecondsPerChar`. Used by `generateAudio`
  /// to decide whether a phrase is long enough to warrant auto-chunking.
  public static func estimateDuration(text: String) -> TimeInterval {
    return Double(text.count) * estimatedSecondsPerChar
  }

  /// Minimum chunk size in characters. Chunks shorter than this are merged forward
  /// to prevent voice drift from high-temperature sampling on runt chunks.
  /// See FIXME.md in Produciesta for root-cause analysis.
  public static let minimumChunkSize = 100

  /// Split text at sentence boundaries and pack into duration-bounded chunks.
  ///
  /// Uses Foundation's ICU-backed sentence segmenter (`enumerateSubstrings(.bySentences)`)
  /// to find boundaries — handles abbreviations (`Dr.`, `Mr.`, `e.g.`), decimals
  /// (`3.14`), and ellipses correctly without a regex's failure modes.
  /// Sentences are then packed greedily into chunks no longer than `maxDuration`
  /// seconds (estimated via `estimateDuration`). A single sentence longer than
  /// `maxDuration` is emitted as its own oversized chunk rather than mid-sentence-cut.
  ///
  /// **Minimum chunk size enforcement**: Chunks shorter than `minimumChunkSize`
  /// characters are merged forward into the next sentence to prevent voice drift
  /// from adaptive temperature inversion (short chunks get higher temperature,
  /// which is backwards for voice-clone stability).
  ///
  /// - Parameters:
  ///   - text: The text to split.
  ///   - maxDuration: Maximum estimated duration per chunk, in seconds.
  /// - Returns: An array of non-empty chunk strings. Returns `[trimmed]` for input
  ///   with no detectable sentence boundaries; returns `[]` for empty/whitespace-only input.
  public static func splitAtSentences(text: String, maxDuration: TimeInterval) -> [String] {
    var sentences: [String] = []
    text.enumerateSubstrings(
      in: text.startIndex..<text.endIndex,
      options: .bySentences
    ) { substring, _, _, _ in
      if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        sentences.append(s)
      }
    }

    if sentences.isEmpty {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? [] : [trimmed]
    }

    var chunks: [String] = []
    var currentChunk = ""

    for sentence in sentences {
      let candidate = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence

      // Check if adding this sentence would exceed maxDuration
      if estimateDuration(text: candidate) > maxDuration && !currentChunk.isEmpty {
        // Emit current chunk only if it meets minimum size, otherwise keep accumulating
        if currentChunk.count >= minimumChunkSize {
          chunks.append(currentChunk)
          currentChunk = sentence
        } else {
          // Runt chunk — merge forward even if it exceeds maxDuration
          currentChunk = candidate
        }
      } else {
        currentChunk = candidate
      }
    }

    if !currentChunk.isEmpty {
      // Trailing runt: merge backward into the previous chunk so we never emit
      // a sub-minimumChunkSize tail (the in-loop logic only merges forward).
      if currentChunk.count < minimumChunkSize, let last = chunks.popLast() {
        chunks.append(last + " " + currentChunk)
      } else {
        chunks.append(currentChunk)
      }
    }

    return chunks
  }

  /// Generate a silence MLXArray of the given duration at `sampleRate` Hz.
  ///
  /// Returns a 1-D float array of zeros, suitable for concatenation with TTS
  /// output along axis 0. Used to insert natural pauses between chunks in
  /// auto-chunked output.
  public static func generateSilenceArray(duration: TimeInterval, sampleRate: Int) -> MLXArray {
    let numSamples = max(0, Int(duration * Double(sampleRate)))
    return MLXArray([Float](repeating: 0.0, count: numSamples))
  }
}
