//
//  VoxAltaError.swift
//  SwiftVoxAlta
//
//  Error types for VoxAlta voice synthesis operations.
//

import Foundation

/// Errors that can occur during VoxAlta voice cloning and synthesis operations.
public enum VoxAltaError: Error, LocalizedError, Sendable {
    /// Voice cloning from reference audio failed.
    case cloningFailed(String)

    /// The requested TTS model is not available or not downloaded.
    case modelNotAvailable(String)

    /// The requested voice has not been loaded into the provider's cache.
    case voiceNotLoaded(String)

    /// Insufficient system memory to load the requested model.
    case insufficientMemory(available: Int, required: Int)

    /// Audio export or format conversion failed.
    case audioExportFailed(String)

    /// Exporting a voice to .vox format failed.
    case voxExportFailed(String)

    /// Importing a voice from .vox format failed.
    case voxImportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cloningFailed(let detail):
            return "Voice cloning failed: \(detail)"
        case .modelNotAvailable(let model):
            return "Model not available: \(model). Ensure the model has been downloaded."
        case .voiceNotLoaded(let voiceId):
            return "Voice '\(voiceId)' is not loaded. Call loadVoice(id:clonePromptData:) before generating audio."
        case .insufficientMemory(let available, let required):
            return "Insufficient memory: \(available) bytes available, \(required) bytes required."
        case .audioExportFailed(let detail):
            return "Audio export failed: \(detail)"
        case .voxExportFailed(let detail):
            return "VOX export failed: \(detail)"
        case .voxImportFailed(let detail):
            return "VOX import failed: \(detail)"
        }
    }
}
