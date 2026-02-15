//
//  AppleSiliconInfo.swift
//  SwiftVoxAlta
//
//  Apple Silicon generation detection for runtime optimization hints.
//  Detects M1 through M5 chips to identify Neural Accelerator availability.
//

import Foundation

/// Apple Silicon generation enumeration.
///
/// Used to detect which Apple Silicon generation is running on the current system,
/// primarily to identify whether M5 Neural Accelerators are available for MLX
/// performance optimizations.
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

    /// Whether this chip generation includes M5 Neural Accelerators.
    ///
    /// Neural Accelerators are hardware acceleration units introduced in M5 (2025)
    /// that provide significant performance improvements for MLX workloads on macOS 26.2+.
    ///
    /// - Returns: `true` for M5/M5 Pro/M5 Max/M5 Ultra, `false` otherwise
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
    /// This property queries the CPU brand string via `sysctlbyname` to determine
    /// which Apple Silicon chip is running. Detection is performed once at first access
    /// and cached for the lifetime of the process.
    ///
    /// - Returns: The detected `AppleSiliconGeneration`, or `.unknown` if detection fails
    public static var current: AppleSiliconGeneration {
        _current
    }

    /// Cached detection result.
    private static let _current: AppleSiliconGeneration = {
        detectGeneration()
    }()

    /// Detect the Apple Silicon generation by querying the CPU brand string.
    ///
    /// Uses `sysctlbyname("machdep.cpu.brand_string")` to read the CPU identifier
    /// string (e.g., "Apple M5 Pro") and matches it against known patterns.
    ///
    /// - Returns: The detected generation, or `.unknown` if no match
    private static func detectGeneration() -> AppleSiliconGeneration {
        var size = 0
        // First call to get the required buffer size
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        guard size > 0 else {
            return .unknown
        }

        // Allocate buffer and retrieve the brand string
        var brandString = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brandString, &size, nil, 0)

        let cpuBrand = String(cString: brandString).trimmingCharacters(in: .whitespaces)

        // Match against known patterns (order matters - check longer strings first)
        if cpuBrand.contains("M5 Ultra") {
            return .m5Ultra
        } else if cpuBrand.contains("M5 Max") {
            return .m5Max
        } else if cpuBrand.contains("M5 Pro") {
            return .m5Pro
        } else if cpuBrand.contains("M5") {
            return .m5
        } else if cpuBrand.contains("M4 Ultra") {
            return .m4Ultra
        } else if cpuBrand.contains("M4 Max") {
            return .m4Max
        } else if cpuBrand.contains("M4 Pro") {
            return .m4Pro
        } else if cpuBrand.contains("M4") {
            return .m4
        } else if cpuBrand.contains("M3 Ultra") {
            return .m3Ultra
        } else if cpuBrand.contains("M3 Max") {
            return .m3Max
        } else if cpuBrand.contains("M3 Pro") {
            return .m3Pro
        } else if cpuBrand.contains("M3") {
            return .m3
        } else if cpuBrand.contains("M2 Ultra") {
            return .m2Ultra
        } else if cpuBrand.contains("M2 Max") {
            return .m2Max
        } else if cpuBrand.contains("M2 Pro") {
            return .m2Pro
        } else if cpuBrand.contains("M2") {
            return .m2
        } else if cpuBrand.contains("M1 Ultra") {
            return .m1Ultra
        } else if cpuBrand.contains("M1 Max") {
            return .m1Max
        } else if cpuBrand.contains("M1 Pro") {
            return .m1Pro
        } else if cpuBrand.contains("M1") {
            return .m1
        } else {
            return .unknown
        }
    }
}
