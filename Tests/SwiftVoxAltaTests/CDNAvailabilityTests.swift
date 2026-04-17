//
//  CDNAvailabilityTests.swift
//  SwiftVoxAltaTests
//
//  Validates that all registered Qwen3-TTS models are available on the Acervo
//  CDN and that config.json downloads correctly for each via SwiftAcervo.
//
//  These tests require network access and download only config.json (~2–5 KB
//  per model). They are excluded from make test-unit via -skip-testing and
//  run explicitly via:
//
//    make test-cdn
//    # or manually:
//    xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS' \
//        -only-testing:SwiftVoxAltaTests/CDNAvailabilityTests

import Foundation
import Testing

@testable import SwiftAcervo
@testable import SwiftVoxAlta

// MARK: - Helpers

private let cdnBase = "https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models"

private func manifestURL(for modelId: String) -> URL {
  URL(string: "\(cdnBase)/\(Acervo.slugify(modelId))/manifest.json")!
}

private func makeTempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("VoxAlta-CDN-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func cleanup(_ dir: URL) {
  try? FileManager.default.removeItem(at: dir)
}

// MARK: - CDN Availability Tests

@Suite("CDN Availability: All Qwen3-TTS Models")
struct CDNAvailabilityTests {

  // MARK: Manifest presence

  @Test("Manifest is accessible on CDN (HTTP 200)", arguments: Qwen3TTSModelRepo.allCases)
  func manifestAccessible(repo: Qwen3TTSModelRepo) async throws {
    let (_, response) = try await URLSession.shared.data(from: manifestURL(for: repo.rawValue))
    let http = try #require(response as? HTTPURLResponse)
    #expect(
      http.statusCode == 200,
      "\(repo.rawValue): manifest returned HTTP \(http.statusCode)"
    )
  }

  @Test("Manifest is valid JSON with required structure", arguments: Qwen3TTSModelRepo.allCases)
  func manifestStructure(repo: Qwen3TTSModelRepo) async throws {
    let (data, response) = try await URLSession.shared.data(from: manifestURL(for: repo.rawValue))
    let http = try #require(response as? HTTPURLResponse)
    try #require(http.statusCode == 200, "Cannot parse manifest: HTTP \(http.statusCode)")

    let json = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any],
      "manifest.json is not a JSON dictionary"
    )

    #expect(json["manifestVersion"] as? Int == 1, "\(repo.rawValue): unexpected manifestVersion")
    #expect(json["modelId"] as? String == repo.rawValue, "\(repo.rawValue): modelId mismatch")

    let files = json["files"] as? [[String: Any]] ?? []
    let paths = Set(files.compactMap { $0["path"] as? String })
    #expect(paths.contains("config.json"), "\(repo.rawValue): manifest missing config.json")
    #expect(
      paths.contains("model.safetensors"), "\(repo.rawValue): manifest missing model.safetensors")
    #expect(
      paths.contains("tokenizer_config.json"),
      "\(repo.rawValue): manifest missing tokenizer_config.json")
  }

  // MARK: config.json download

  @Test("config.json downloads and parses as JSON", arguments: Qwen3TTSModelRepo.allCases)
  func configJsonDownloads(repo: Qwen3TTSModelRepo) async throws {
    let tempBase = try makeTempDir()
    defer { cleanup(tempBase) }

    try await Acervo.download(repo.rawValue, files: ["config.json"], in: tempBase)

    let configPath =
      tempBase
      .appendingPathComponent(Acervo.slugify(repo.rawValue))
      .appendingPathComponent("config.json")

    #expect(
      FileManager.default.fileExists(atPath: configPath.path),
      "\(repo.rawValue): config.json missing after download"
    )

    let data = try Data(contentsOf: configPath)
    let json = try JSONSerialization.jsonObject(with: data)
    #expect(json is [String: Any], "\(repo.rawValue): config.json is not a JSON dictionary")
  }

  @Test(
    "isModelAvailable returns true after config.json download",
    arguments: Qwen3TTSModelRepo.allCases)
  func modelAvailableAfterDownload(repo: Qwen3TTSModelRepo) async throws {
    let tempBase = try makeTempDir()
    defer { cleanup(tempBase) }

    #expect(!Acervo.isModelAvailable(repo.rawValue, in: tempBase))
    try await Acervo.download(repo.rawValue, files: ["config.json"], in: tempBase)
    #expect(
      Acervo.isModelAvailable(repo.rawValue, in: tempBase),
      "\(repo.rawValue): not marked available after config.json download"
    )
  }
}
