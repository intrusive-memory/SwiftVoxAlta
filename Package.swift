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
    .executable(
      name: "diga",
      targets: ["diga"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/intrusive-memory/SwiftHablare.git", .upToNextMajor(from: "6.1.0")),
    .package(
      url: "https://github.com/intrusive-memory/mlx-audio-swift.git", .upToNextMajor(from: "0.7.0")),
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.12.0")),
    .package(
      url: "https://github.com/intrusive-memory/SwiftTuberia.git", .upToNextMajor(from: "0.6.5")),
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),
    .package(
      url: "https://github.com/intrusive-memory/vox-format.git", .upToNextMajor(from: "0.3.1")),
  ],
  targets: [
    .target(
      name: "SwiftVoxAlta",
      dependencies: [
        .product(name: "SwiftHablare", package: "SwiftHablare"),
        .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "Tuberia", package: "SwiftTuberia"),
        .product(name: "VoxFormat", package: "vox-format"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "diga",
      dependencies: [
        "SwiftVoxAlta",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
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
        "diga",
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
