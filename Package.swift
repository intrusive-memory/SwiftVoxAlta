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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/intrusive-memory/SwiftHablare.git", branch: "development"),
        .package(url: "https://github.com/intrusive-memory/SwiftCompartido.git", branch: "development"),
        .package(url: "https://github.com/intrusive-memory/SwiftBruja.git", branch: "main"),
        .package(url: "https://github.com/intrusive-memory/mlx-audio-swift.git", branch: "development"),
    ],
    targets: [
        .target(
            name: "SwiftVoxAlta",
            dependencies: [
                .product(name: "SwiftHablare", package: "SwiftHablare"),
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
                .product(name: "SwiftBruja", package: "SwiftBruja"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SwiftVoxAltaTests",
            dependencies: [
                "SwiftVoxAlta",
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
