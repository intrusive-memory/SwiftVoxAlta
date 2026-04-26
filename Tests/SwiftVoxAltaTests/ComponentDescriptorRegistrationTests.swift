//
//  ComponentDescriptorRegistrationTests.swift
//  SwiftVoxAltaTests
//
//  Verifies that SwiftVoxAlta registers a ComponentDescriptor for every
//  Qwen3-TTS variant with correct metadata. Download, checksum validation,
//  caching, file-presence, and CDN availability are owned by SwiftAcervo
//  and are not retested here.
//

import Foundation
import Testing

@testable import SwiftAcervo
@testable import SwiftVoxAlta

@Suite("ComponentDescriptor Registration")
struct ComponentDescriptorRegistrationTests {

  @Test(
    "Every Qwen3-TTS variant registers a ComponentDescriptor", arguments: Qwen3TTSModelRepo.allCases
  )
  func everyVariantRegistered(repo: Qwen3TTSModelRepo) throws {
    _ = VoxAltaModelManager()

    let descriptor = try #require(Acervo.component(repo.componentId))

    #expect(descriptor.id == repo.componentId)
    #expect(descriptor.type == .languageModel)
    #expect(descriptor.repoId == repo.rawValue)
    #expect(!descriptor.displayName.isEmpty)
    #expect(descriptor.minimumMemoryBytes > 0)
    // Bare descriptor: files + estimatedSizeBytes are populated lazily by
    // SwiftAcervo on first ensureComponentReady call. A freshly registered
    // descriptor reports needsHydration == true.
    #expect(
      descriptor.needsHydration == true,
      "Newly registered descriptors must be bare (manifest-driven)")
    #expect(descriptor.files.isEmpty)
  }

  @Test("Base 1.7B descriptor reports the expected memory budget")
  func base17BMemoryBudgetMatchesExpectation() throws {
    _ = VoxAltaModelManager()

    let descriptor = try #require(Acervo.component("qwen3-tts-base-1.7b"))

    #expect(descriptor.minimumMemoryBytes == 3_400_000_000)
    #expect(descriptor.metadata["deprecated"] != "true")
  }

  @Test("Deprecated 4-bit variant is flagged in metadata and display name")
  func deprecatedVariantFlagged() throws {
    _ = VoxAltaModelManager()

    let descriptor = try #require(Acervo.component("qwen3-tts-base-1.7b-4bit"))

    #expect(descriptor.metadata["deprecated"] == "true")
    #expect(descriptor.displayName.contains("Deprecated"))
  }
}
