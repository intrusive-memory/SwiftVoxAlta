//
//  VoxAltaConfig.swift
//  SwiftVoxAlta
//
//  Configuration for VoxAlta voice design and rendering pipeline.
//

import Foundation

/// Output audio format for rendered speech.
public enum AudioOutputFormat: String, Codable, Sendable {
    case wav
    case aiff
    case m4a
}

/// Configuration controlling VoxAlta's model selection, candidate generation,
/// and output format.
public struct VoxAltaConfig: Codable, Sendable {
    /// HuggingFace repo ID for the Qwen3-TTS VoiceDesign model (used for generating voice candidates).
    public let designModel: String

    /// HuggingFace repo ID for the Qwen3-TTS Base model (used for rendering dialogue audio).
    public let renderModel: String

    /// Model identifier for the SwiftBruja LLM used for character analysis.
    public let analysisModel: String

    /// Number of voice candidates to generate during voice design.
    public let candidateCount: Int

    /// Audio output format for rendered speech.
    public let outputFormat: AudioOutputFormat

    public init(
        designModel: String,
        renderModel: String,
        analysisModel: String,
        candidateCount: Int,
        outputFormat: AudioOutputFormat
    ) {
        self.designModel = designModel
        self.renderModel = renderModel
        self.analysisModel = analysisModel
        self.candidateCount = candidateCount
        self.outputFormat = outputFormat
    }

    /// Default configuration using standard Qwen3-TTS models.
    public static let `default` = VoxAltaConfig(
        designModel: "mlx-community/Qwen3-TTS-12Hz-VoiceDesign-1.7B-bf16",
        renderModel: "mlx-community/Qwen3-TTS-12Hz-Base-1.7B-bf16",
        analysisModel: "mlx-community/Qwen3-4B-4bit",
        candidateCount: 3,
        outputFormat: .wav
    )
}
