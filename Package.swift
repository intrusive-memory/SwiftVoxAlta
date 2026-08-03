// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
//
// When this manifest is evaluated as a transitive dependency inside Xcode's
// `SourcePackages/checkouts/` or SwiftPM's `.build/checkouts/`, every other
// dependency lives as a sibling in the same directory. Treating those as
// in-development local paths produces conflicting package identities, so we
// must skip the sibling shortcut in that context.
let manifestDir = (#filePath as NSString).deletingLastPathComponent
let isSPMCheckout =
  manifestDir.contains("/SourcePackages/checkouts/")
  || manifestDir.contains("/.build/checkouts/")
let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
let useLocalSiblings = !isCI && !isSPMCheckout

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

/// Same sibling-priority pattern as ``sibling(_:remote:from:)`` but pins to a
/// remote branch when no local sibling exists. Use only when a temporary
/// pre-release dependency on a feature branch is required; switch back to the
/// version-pinned ``sibling(_:remote:from:)`` once the upstream tags a release.
func sibling(_ name: String, remote: String, branch: String) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, branch: branch)
}

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
    sibling(
      "SwiftHablare",
      remote: "https://github.com/intrusive-memory/SwiftHablare.git",
      from: "6.2.0"),
    // mlx-audio-swift 0.10.0 adopts swift-tokenizers 0.7.x
    // (`.upToNextMinor(from: "0.7.1")`), matching SwiftTuberia 0.8.0. The two now
    // co-resolve on tokenizers 0.7.x, so the earlier 0.5.x/0.6.x pin concerns no
    // longer apply. Floor tracks the latest published release.
    sibling(
      "mlx-audio-swift",
      remote: "https://github.com/intrusive-memory/mlx-audio-swift.git",
      from: "0.10.0"),
    sibling(
      "SwiftAcervo",
      remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
      from: "0.25.0"),
    // SwiftTuberia 0.8.x uses swift-tokenizers 0.7.x; mlx-audio-swift 0.10.0 now
    // also adopts tokenizers 0.7.x, so they co-resolve. Floor tracks latest release.
    sibling(
      "SwiftTuberia",
      remote: "https://github.com/intrusive-memory/SwiftTuberia.git",
      from: "0.8.0"),
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.8.2")),
    sibling(
      "vox-format",
      remote: "https://github.com/intrusive-memory/vox-format.git",
      from: "0.4.1"),
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
