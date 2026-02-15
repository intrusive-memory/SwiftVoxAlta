// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftVoxAlta",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
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
        .package(url: "https://github.com/intrusive-memory/SwiftHablare.git", branch: "development"),
        .package(url: "https://github.com/intrusive-memory/SwiftCompartido.git", branch: "development"),
        .package(url: "https://github.com/intrusive-memory/SwiftBruja.git", branch: "main"),
        .package(url: "https://github.com/intrusive-memory/mlx-audio-swift.git", revision: "eedb0f5a34163976d499814d469373cfe7e05ae3"),
        .package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftVoxAlta",
            dependencies: [
                .product(name: "SwiftHablare", package: "SwiftHablare"),
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
                .product(name: "SwiftBruja", package: "SwiftBruja"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
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
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DigaTests",
            dependencies: [
                "diga",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
