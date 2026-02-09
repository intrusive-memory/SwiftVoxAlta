//
//  VoxAltaError.swift
//  SwiftVoxAlta
//
//  Error types for VoxAlta voice design and synthesis operations.
//

import Foundation

/// Errors that can occur during VoxAlta voice design, cloning, and synthesis operations.
public enum VoxAltaError: Error, LocalizedError, Sendable {
    /// Voice design failed to generate a valid voice from the character profile.
    case voiceDesignFailed(String)

    /// Voice cloning from reference audio failed.
    case cloningFailed(String)

    /// The requested TTS model is not available or not downloaded.
    case modelNotAvailable(String)

    /// The requested voice has not been loaded into the provider's cache.
    case voiceNotLoaded(String)

    /// Character profile analysis via LLM failed.
    case profileAnalysisFailed(String)

    /// Insufficient system memory to load the requested model.
    case insufficientMemory(available: Int, required: Int)

    /// Audio export or format conversion failed.
    case audioExportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .voiceDesignFailed(let detail):
            return "Voice design failed: \(detail)"
        case .cloningFailed(let detail):
            return "Voice cloning failed: \(detail)"
        case .modelNotAvailable(let model):
            return "Model not available: \(model). Ensure the model has been downloaded."
        case .voiceNotLoaded(let voiceId):
            return "Voice '\(voiceId)' is not loaded. Call loadVoice(id:clonePromptData:) before generating audio."
        case .profileAnalysisFailed(let detail):
            return "Character profile analysis failed: \(detail)"
        case .insufficientMemory(let available, let required):
            return "Insufficient memory: \(available) bytes available, \(required) bytes required."
        case .audioExportFailed(let detail):
            return "Audio export failed: \(detail)"
        }
    }
}
