//
//  AppleSiliconInfo.swift
//  SwiftVoxAlta
//
//  Apple Silicon generation detection for runtime optimization hints.
//  Thin wrapper around SwiftTubería's DeviceCapability.
//

import Foundation
import Tuberia

/// Apple Silicon generation enumeration.
///
/// Used to detect which Apple Silicon generation is running on the current system,
/// primarily to identify whether M5 Neural Accelerators are available for MLX
/// performance optimizations.
///
/// This enum preserves the full public API surface for backward compatibility
/// with callers in Produciesta, SwiftEchada, and other consumers. Internally,
/// all detection logic delegates to `DeviceCapability.current`.
public enum AppleSiliconGeneration: String, Sendable, CaseIterable {
    /// Apple M1 (2020) - First Apple Silicon Mac
    case m1 = "M1"

    /// Apple M1 Pro (2021) - Enhanced M1 with more GPU cores
    case m1Pro = "M1 Pro"

    /// Apple M1 Max (2021) - High-end M1 with maximum GPU cores
    case m1Max = "M1 Max"

    /// Apple M1 Ultra (2022) - Dual M1 Max design
    case m1Ultra = "M1 Ultra"

    /// Apple M2 (2022) - Second generation Apple Silicon
    case m2 = "M2"

    /// Apple M2 Pro (2023) - Enhanced M2 with more GPU cores
    case m2Pro = "M2 Pro"

    /// Apple M2 Max (2023) - High-end M2 with maximum GPU cores
    case m2Max = "M2 Max"

    /// Apple M2 Ultra (2023) - Dual M2 Max design
    case m2Ultra = "M2 Ultra"

    /// Apple M3 (2023) - Third generation Apple Silicon
    case m3 = "M3"

    /// Apple M3 Pro (2023) - Enhanced M3 with more GPU cores
    case m3Pro = "M3 Pro"

    /// Apple M3 Max (2023) - High-end M3 with maximum GPU cores
    case m3Max = "M3 Max"

    /// Apple M3 Ultra (2024) - Dual M3 Max design
    case m3Ultra = "M3 Ultra"

    /// Apple M4 (2024) - Fourth generation Apple Silicon
    case m4 = "M4"

    /// Apple M4 Pro (2024) - Enhanced M4 with more GPU cores
    case m4Pro = "M4 Pro"

    /// Apple M4 Max (2024) - High-end M4 with maximum GPU cores
    case m4Max = "M4 Max"

    /// Apple M4 Ultra (2024) - Dual M4 Max design
    case m4Ultra = "M4 Ultra"

    /// Apple M5 (2025) - Fifth generation Apple Silicon with Neural Accelerators
    case m5 = "M5"

    /// Apple M5 Pro (2025) - Enhanced M5 with more GPU cores and Neural Accelerators
    case m5Pro = "M5 Pro"

    /// Apple M5 Max (2025) - High-end M5 with maximum GPU cores and Neural Accelerators
    case m5Max = "M5 Max"

    /// Apple M5 Ultra (2025) - Dual M5 Max design with Neural Accelerators
    case m5Ultra = "M5 Ultra"

    /// Unknown or unrecognized Apple Silicon chip
    case unknown = "Unknown"

    /// Whether this chip generation includes Neural Accelerators.
    ///
    /// Returns `true` for M5 family chips, which are the first Apple Silicon generation
    /// with dedicated Neural Accelerator hardware for MLX inference.
    ///
    /// Note: This is a per-case property reflecting the capability of the chip generation
    /// represented by this enum case, not the hardware of the currently running machine.
    public var hasNeuralAccelerators: Bool {
        switch self {
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return true
        default:
            return false
        }
    }

    /// The current Apple Silicon generation detected on this system.
    ///
    /// Delegates chip detection to `DeviceCapability.current.chipGeneration` and
    /// maps to the local `AppleSiliconGeneration` enum. Detection is cached by
    /// `DeviceCapability.current` (a static let) for the lifetime of the process.
    ///
    /// - Returns: The detected `AppleSiliconGeneration`, or `.unknown` if detection fails.
    public static var current: AppleSiliconGeneration {
        mapFromDeviceCapability(DeviceCapability.current.chipGeneration)
    }

    // MARK: - Internal Mapping

    /// Maps a `DeviceCapability.AppleSiliconGeneration` case to `AppleSiliconGeneration`.
    ///
    /// DeviceCapability uses lowercase raw values (e.g., `"m1Pro"`) while
    /// AppleSiliconGeneration uses human-readable raw values (e.g., `"M1 Pro"`).
    /// The mapping is by case identity, not raw value comparison.
    internal static func mapFromDeviceCapability(
        _ dc: DeviceCapability.AppleSiliconGeneration
    ) -> AppleSiliconGeneration {
        switch dc {
        case .m1:       return .m1
        case .m1Pro:    return .m1Pro
        case .m1Max:    return .m1Max
        case .m1Ultra:  return .m1Ultra
        case .m2:       return .m2
        case .m2Pro:    return .m2Pro
        case .m2Max:    return .m2Max
        case .m2Ultra:  return .m2Ultra
        case .m3:       return .m3
        case .m3Pro:    return .m3Pro
        case .m3Max:    return .m3Max
        case .m3Ultra:  return .m3Ultra
        case .m4:       return .m4
        case .m4Pro:    return .m4Pro
        case .m4Max:    return .m4Max
        case .m4Ultra:  return .m4Ultra
        case .m5:       return .m5
        case .m5Pro:    return .m5Pro
        case .m5Max:    return .m5Max
        case .m5Ultra:  return .m5Ultra
        case .unknown:  return .unknown
        }
    }
}
