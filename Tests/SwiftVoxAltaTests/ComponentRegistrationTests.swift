//
//  ComponentRegistrationTests.swift
//  SwiftVoxAltaTests
//
//  Tests verifying that all 7 Qwen3-TTS component descriptors are registered
//  and queryable via the SwiftAcervo Component Registry.
//

import Testing
import Foundation
import SwiftAcervo
@testable import SwiftVoxAlta

@Suite("Acervo Component Registration")
struct ComponentRegistrationTests {

    /// Ensure components are registered before each test by creating a manager instance.
    /// VoxAltaModelManager.init() triggers the lazy _registerQwen3TTSComponents.
    private func ensureRegistered() {
        _ = VoxAltaModelManager()
    }

    @Test("All 7 TTS model variants are registered in Acervo")
    func allSevenVariantsAreRegistered() {
        ensureRegistered()
        let allComponents = Acervo.registeredComponents()
        let ttsComponents = allComponents.filter { $0.id.hasPrefix("qwen3-tts") }
        #expect(ttsComponents.count >= 7, "Expected at least 7 qwen3-tts components, found \(ttsComponents.count)")
    }

    @Test("Component IDs match Qwen3TTSModelRepo.componentId for all cases")
    func componentIDsMatchEnumCases() {
        ensureRegistered()
        for repo in Qwen3TTSModelRepo.allCases {
            let descriptor = Acervo.component(repo.componentId)
            #expect(descriptor != nil, "Missing ComponentDescriptor for \(repo.componentId)")
            if let descriptor {
                #expect(descriptor.id == repo.componentId,
                        "Descriptor ID '\(descriptor.id)' does not match expected '\(repo.componentId)'")
            }
        }
    }

    @Test("4-bit variant has deprecated metadata")
    func fourBitVariantIsDeprecated() {
        ensureRegistered()
        let descriptor = Acervo.component(Qwen3TTSModelRepo.base1_7B_4bit.componentId)
        #expect(descriptor != nil, "4-bit ComponentDescriptor should be registered")
        #expect(descriptor?.metadata["deprecated"] == "true",
                "4-bit variant should have metadata['deprecated'] == 'true'")
    }

    @Test("ComponentDescriptor huggingFaceRepo matches Qwen3TTSModelRepo.rawValue for all variants")
    func huggingFaceRepoMatchesRawValue() {
        ensureRegistered()
        for repo in Qwen3TTSModelRepo.allCases {
            guard let descriptor = Acervo.component(repo.componentId) else {
                Issue.record("Missing ComponentDescriptor for \(repo.componentId)")
                continue
            }
            #expect(descriptor.huggingFaceRepo == repo.rawValue,
                    "HuggingFace repo mismatch for \(repo.componentId): expected '\(repo.rawValue)', got '\(descriptor.huggingFaceRepo)'")
        }
    }

    @Test("ComponentDescriptor minimumMemoryBytes is positive for all variants")
    func minimumMemoryBytesIsPositiveForAll() {
        ensureRegistered()
        for repo in Qwen3TTSModelRepo.allCases {
            guard let descriptor = Acervo.component(repo.componentId) else {
                Issue.record("Missing ComponentDescriptor for \(repo.componentId)")
                continue
            }
            #expect(descriptor.minimumMemoryBytes > 0,
                    "minimumMemoryBytes for \(repo.componentId) should be positive, got \(descriptor.minimumMemoryBytes)")
        }
    }

    @Test("All non-deprecated variants are not marked deprecated")
    func activeVariantsAreNotDeprecated() {
        ensureRegistered()
        let activeRepos: [Qwen3TTSModelRepo] = [
            .base1_7B, .base0_6B, .customVoice1_7B,
            .customVoice0_6B, .voiceDesign1_7B, .base1_7B_8bit,
        ]
        for repo in activeRepos {
            let descriptor = Acervo.component(repo.componentId)
            #expect(descriptor != nil, "Missing component for \(repo.componentId)")
            #expect(descriptor?.metadata["deprecated"] != "true",
                    "\(repo.componentId) should not be deprecated")
        }
    }

    @Test("Each ComponentDescriptor declares the four required model files")
    func componentDescriptorsDeclareRequiredFiles() {
        ensureRegistered()
        let expectedFiles = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]
        for repo in Qwen3TTSModelRepo.allCases {
            guard let descriptor = Acervo.component(repo.componentId) else {
                Issue.record("Missing ComponentDescriptor for \(repo.componentId)")
                continue
            }
            let filePaths = descriptor.files.map { $0.relativePath }
            for expectedFile in expectedFiles {
                #expect(filePaths.contains(expectedFile),
                        "\(repo.componentId) is missing '\(expectedFile)' in its file list")
            }
        }
    }

    @Test("1.7B variants have larger minimumMemoryBytes than 0.6B variants")
    func memoryOrdering1_7BLargerThan0_6B() {
        ensureRegistered()
        let base1_7B = Acervo.component(Qwen3TTSModelRepo.base1_7B.componentId)!.minimumMemoryBytes
        let base0_6B = Acervo.component(Qwen3TTSModelRepo.base0_6B.componentId)!.minimumMemoryBytes
        #expect(base1_7B > base0_6B, "1.7B base model should require more memory than 0.6B base model")
    }

    @Test("Qwen3TTSModelRepo.componentId values are all unique")
    func componentIDsAreUnique() {
        let ids = Qwen3TTSModelRepo.allCases.map { $0.componentId }
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count,
                "Component IDs should be unique: found \(ids.count) cases but only \(uniqueIDs.count) unique IDs")
    }
}
