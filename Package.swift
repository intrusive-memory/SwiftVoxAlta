// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwiftVoxAlta",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(
      name: "SwiftVoxAlta",
      targets: ["SwiftVoxAlta"]
    ),
    .library(
      name: "DigaCLICore",
      targets: ["DigaCLICore"]
    ),
    .executable(
      name: "diga",
      targets: ["diga"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/intrusive-memory/SwiftHablare.git", .upToNextMajor(from: "6.2.0")),
    // mlx-audio-swift 0.9.0 keeps swift-tokenizers pinned to
    // `.upToNextMinor(from: "0.5.0")` (`>= 0.5.0, < 0.6.0`), so the risky
    // 0.6.x UniFFI/Rust-artifactbundle tokenizer does NOT leak in transitively
    // — the earlier 0.8.x cap (which anticipated 0.9.0 adopting 0.6.x) no
    // longer applies. Floor tracks the latest published release.
    .package(
      url: "https://github.com/intrusive-memory/mlx-audio-swift.git", .upToNextMajor(from: "0.9.0")),
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.23.0")),
    // SwiftTuberia >= 0.7.5 moved to swift-tokenizers 0.7.x; mlx-audio-swift 0.9.0
    // pins swift-tokenizers to 0.5.x, so 0.7.4 is the last version that co-resolves.
    // Do NOT bump past 0.7.4 until mlx-audio-swift adopts tokenizers 0.7.x.
    .package(
      url: "https://github.com/intrusive-memory/SwiftTuberia.git", .upToNextMajor(from: "0.7.4")),
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),
    .package(
      url: "https://github.com/intrusive-memory/vox-format.git", .upToNextMajor(from: "0.4.1")),
  ],
  targets: [
    .target(
      name: "SwiftVoxAlta",
      dependencies: [
        .product(name: "SwiftHablare", package: "SwiftHablare"),
        .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
        .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "Tuberia", package: "SwiftTuberia"),
        .product(name: "VoxFormat", package: "vox-format"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .target(
      name: "DigaCLICore",
      dependencies: [
        "SwiftVoxAlta",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "diga",
      dependencies: [
        "DigaCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/diga",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftVoxAltaTests",
      dependencies: [
        "SwiftVoxAlta",
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "Tuberia", package: "SwiftTuberia"),
        .product(name: "VoxFormat", package: "vox-format"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "DigaTests",
      dependencies: [
        "DigaCLICore",
        "SwiftVoxAlta",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "VoxFormat", package: "vox-format"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
