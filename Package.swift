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
    // mlx-audio-swift 0.10.0 adopts swift-tokenizers 0.7.x
    // (`.upToNextMinor(from: "0.7.1")`), matching SwiftTuberia 0.8.0. The two now
    // co-resolve on tokenizers 0.7.x, so the earlier 0.5.x/0.6.x pin concerns no
    // longer apply. Floor tracks the latest published release.
    .package(
      url: "https://github.com/intrusive-memory/mlx-audio-swift.git", .upToNextMajor(from: "0.10.0")
    ),
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.25.0")),
    // SwiftTuberia 0.8.x uses swift-tokenizers 0.7.x; mlx-audio-swift 0.10.0 now
    // also adopts tokenizers 0.7.x, so they co-resolve. Floor tracks latest release.
    .package(
      url: "https://github.com/intrusive-memory/SwiftTuberia.git", .upToNextMajor(from: "0.8.0")),
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.8.2")),
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
