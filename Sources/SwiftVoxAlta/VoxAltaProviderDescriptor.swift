//
//  VoxAltaProviderDescriptor.swift
//  SwiftVoxAlta
//
//  Factory for creating a VoiceProviderDescriptor for VoxAlta registration
//  with the SwiftHablare VoiceProviderRegistry.
//

import Foundation
import SwiftHablare

/// Factory for creating a `VoiceProviderDescriptor` suitable for registration
/// with SwiftHablare's `VoiceProviderRegistry`.
///
/// Usage:
/// ```swift
/// let registry = VoiceProviderRegistry.shared
/// await registry.register(VoxAltaProviderDescriptor.descriptor())
/// ```
public enum VoxAltaProviderDescriptor: Sendable {

    /// Create a `VoiceProviderDescriptor` for the VoxAlta voice provider.
    ///
    /// - Parameter modelManager: The model manager to use when constructing
    ///   `VoxAltaVoiceProvider` instances. Defaults to a new instance.
    /// - Returns: A descriptor that can be registered with `VoiceProviderRegistry`.
    public static func descriptor(
        modelManager: VoxAltaModelManager = VoxAltaModelManager()
    ) -> VoiceProviderDescriptor {
        VoiceProviderDescriptor(
            id: "voxalta",
            displayName: "VoxAlta (On-Device)",
            isEnabledByDefault: false,
            requiresConfiguration: true,
            makeProvider: { VoxAltaVoiceProvider(modelManager: modelManager) }
        )
    }
}
