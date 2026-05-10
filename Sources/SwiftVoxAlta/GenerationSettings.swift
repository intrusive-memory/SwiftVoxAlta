//
//  GenerationSettings.swift
//  SwiftVoxAlta
//
//  Tunable parameters for Qwen3-TTS audio generation.
//

import Foundation

/// Parameters that control the sampling behavior of Qwen3-TTS audio generation.
///
/// These settings directly affect audio quality and consistency. Lower temperature
/// and topP values produce more stable, predictable speech at the cost of naturalness.
/// Higher values introduce more variation but risk garbled or incoherent output.
///
/// ## Usage
/// ```swift
/// // Use defaults (recommended starting point)
/// let settings = GenerationSettings.default
///
/// // Customize for more stable output
/// let stable = GenerationSettings(temperature: 0.5, topP: 0.8)
///
/// // Pass to VoiceLockManager
/// let audio = try await VoiceLockManager.generateAudio(
///     text: "Hello",
///     voiceLock: lock,
///     settings: settings,
///     modelManager: manager
/// )
/// ```
public struct GenerationSettings: Codable, Sendable, Equatable {

  /// Sampling temperature. Controls randomness in token selection.
  ///
  /// - `0.3–0.5`: Very stable, slightly robotic
  /// - `0.6–0.7`: Balanced stability and naturalness (recommended)
  /// - `0.8–1.0`: More expressive but higher risk of garbled output
  public let temperature: Float

  /// Nucleus sampling threshold. Only tokens within the top-P cumulative
  /// probability mass are considered.
  ///
  /// - `0.8`: Conservative, fewer token choices
  /// - `0.9`: Balanced (recommended)
  /// - `0.95–1.0`: Permissive, may introduce artifacts
  public let topP: Float

  /// Penalty applied to repeated tokens. Discourages the model from
  /// generating the same audio tokens in a loop.
  ///
  /// - `1.0`: No penalty
  /// - `1.1–1.3`: Light penalty (recommended)
  /// - `1.5+`: Aggressive penalty, can distort output
  public let repetitionPenalty: Float

  /// Maximum number of audio tokens to generate per phrase.
  ///
  /// Higher values support longer utterances but increase generation time.
  /// At 12Hz token rate, 16384 tokens ≈ 22 minutes of audio.
  public let maxTokens: Int

  /// Auto-chunk long phrases at sentence boundaries before TTS generation.
  ///
  /// In ICL voice cloning, the reference audio codes anchor prosody only as long
  /// as they remain a meaningful fraction of the model's context. As a single
  /// phrase grows past ~10 seconds, the reference becomes a vanishing fraction
  /// (the "TRIM ratio" drops below ~0.25) and prosody drifts away from the
  /// reference voice. Chunking at sentence boundaries keeps each generation
  /// short enough to maintain a strong anchor.
  ///
  /// When `true` and the estimated duration exceeds `chunkTargetDuration`,
  /// `VoiceLockManager.generateAudio` splits the text at sentence boundaries
  /// (Foundation's ICU-backed segmenter), generates each chunk reusing the same
  /// clone prompt, and concatenates the results with `chunkPauseDuration` of
  /// silence between chunks. The behavior is transparent to callers.
  public let enableAutoChunking: Bool

  /// Target maximum duration (seconds) for a single TTS generation chunk.
  ///
  /// When `enableAutoChunking` is `true`, phrases whose estimated duration
  /// exceeds this value are split at sentence boundaries and packed into
  /// chunks no longer than this. Lower values produce stronger prosody anchors
  /// (less drift) but more chunks and more inter-chunk pauses.
  ///
  /// - `8.0`: Aggressive — TRIM ratio ~0.35, more pauses
  /// - `10.0`: Balanced
  /// - `12.0`: Recommended — TRIM ratio ~0.25, fewer pauses
  public let chunkTargetDuration: TimeInterval

  /// Silence inserted between chunks (seconds).
  ///
  /// Provides a natural breath pause at sentence boundaries created by chunking.
  /// Has no effect when chunking is disabled or the phrase fits in a single chunk.
  public let chunkPauseDuration: TimeInterval

  public init(
    temperature: Float = 0.7,
    topP: Float = 0.9,
    repetitionPenalty: Float = 1.3,
    maxTokens: Int = 16384,
    enableAutoChunking: Bool = true,
    chunkTargetDuration: TimeInterval = 12.0,
    chunkPauseDuration: TimeInterval = 0.25
  ) {
    self.temperature = temperature
    self.topP = topP
    self.repetitionPenalty = repetitionPenalty
    self.maxTokens = maxTokens
    self.enableAutoChunking = enableAutoChunking
    self.chunkTargetDuration = chunkTargetDuration
    self.chunkPauseDuration = chunkPauseDuration
  }

  /// Recommended defaults for voice-cloned speech generation.
  ///
  /// Tuned for consistent, intelligible output with natural-sounding variation.
  public static let `default` = GenerationSettings()
}
