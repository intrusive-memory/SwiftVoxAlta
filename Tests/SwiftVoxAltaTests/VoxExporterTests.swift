import Foundation
import Testing
import VoxFormat

@testable import SwiftVoxAlta

@Suite("VoxExporter Tests", .acervoEnvironment)
struct VoxExporterTests {

  private func makeTempDir() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("vox-exporter-test-\(UUID().uuidString)", isDirectory: true)
  }

  private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  // MARK: - Path Helpers

  @Test("clonePromptPath returns model-specific path for 1.7B")
  func clonePromptPath1_7B() {
    let path = VoxExporter.clonePromptPath(for: .base1_7B)
    #expect(path == "embeddings/qwen3-tts/1.7b/clone-prompt.bin")
  }

  @Test("clonePromptPath returns model-specific path for 0.6B")
  func clonePromptPath0_6B() {
    let path = VoxExporter.clonePromptPath(for: .base0_6B)
    #expect(path == "embeddings/qwen3-tts/0.6b/clone-prompt.bin")
  }

  @Test("modelSizeSlug returns correct slug")
  func modelSizeSlug() {
    #expect(VoxExporter.modelSizeSlug(for: .base0_6B) == "0.6b")
    #expect(VoxExporter.modelSizeSlug(for: .base1_7B) == "1.7b")
    #expect(VoxExporter.modelSizeSlug(for: .voiceDesign1_7B) == "1.7b")
  }

  @Test("sampleAudioPath returns model-specific path for 1.7B")
  func sampleAudioPath1_7B() {
    let path = VoxExporter.sampleAudioPath(for: .base1_7B)
    #expect(path == "embeddings/qwen3-tts/1.7b/sample-audio.wav")
  }

  @Test("sampleAudioPath returns model-specific path for 0.6B")
  func sampleAudioPath0_6B() {
    let path = VoxExporter.sampleAudioPath(for: .base0_6B)
    #expect(path == "embeddings/qwen3-tts/0.6b/sample-audio.wav")
  }

  // MARK: - Update Operations

  @Test("updateClonePrompt adds prompt to existing .vox")
  func updateClonePrompt() throws {
    let tempDir = makeTempDir()
    defer { cleanup(tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create a minimal .vox file.
    let voxURL = tempDir.appendingPathComponent("update.vox")
    let vox = VoxFile(name: "UpdateTest", description: "Testing clone prompt update flow.")
    try vox.write(to: voxURL)

    // Update with a clone prompt.
    let promptData = Data(repeating: 0xCD, count: 128)
    try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: promptData)

    // Verify the clone prompt is now present.
    let readBack = try VoxFile(contentsOf: voxURL)
    let roundTripped = readBack[VoxExporter.clonePromptPath(for: .base1_7B)]?.data
    #expect(roundTripped == promptData)
  }

  @Test("updateSampleAudio adds sample audio to existing .vox")
  func updateSampleAudio() throws {
    let tempDir = makeTempDir()
    defer { cleanup(tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create a minimal .vox file.
    let voxURL = tempDir.appendingPathComponent("sample.vox")
    let vox = VoxFile(name: "SampleTest", description: "Testing sample audio update flow.")
    try vox.write(to: voxURL)

    // Update with sample audio.
    let sampleData = Data(repeating: 0xAA, count: 256)
    try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

    // Verify the sample audio is now present.
    let readBack = try VoxFile(contentsOf: voxURL)
    let roundTripped = readBack[VoxExporter.sampleAudioPath(for: .base1_7B)]?.data
    #expect(roundTripped == sampleData)
  }

  @Test("updateSampleAudio preserves existing clone prompt")
  func updateSampleAudioPreservesClonePrompt() throws {
    let tempDir = makeTempDir()
    defer { cleanup(tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create a .vox file with a clone prompt.
    let voxURL = tempDir.appendingPathComponent("preserve.vox")
    let vox = VoxFile(
      name: "PreserveTest", description: "Testing that sample audio doesn't clobber clone prompt.")
    let cloneData = Data(repeating: 0xBB, count: 64)
    try vox.add(
      cloneData, at: VoxExporter.clonePromptPath(for: .base1_7B),
      metadata: [
        "model": Qwen3TTSModelRepo.base1_7B.rawValue,
        "engine": "qwen3-tts",
        "format": "bin",
      ])
    try vox.write(to: voxURL)

    // Add sample audio.
    let sampleData = Data(repeating: 0xCC, count: 128)
    try VoxExporter.updateSampleAudio(in: voxURL, sampleAudioData: sampleData)

    // Both binaries should be present.
    let readBack = try VoxFile(contentsOf: voxURL)
    #expect(readBack[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == cloneData)
    #expect(readBack[VoxExporter.sampleAudioPath(for: .base1_7B)]?.data == sampleData)
  }

  // MARK: - VoxFile Write Operations

  @Test("addClonePrompt adds prompt with correct path and metadata")
  func addClonePromptToVoxFile() throws {
    let vox = VoxFile(name: "AddTest", description: "Testing addClonePrompt.")
    let promptData = Data(repeating: 0xEE, count: 96)
    try VoxExporter.addClonePrompt(to: vox, data: promptData, modelRepo: .base0_6B)

    let entry = vox[VoxExporter.clonePromptPath(for: .base0_6B)]
    #expect(entry?.data == promptData)

    // Verify manifest embedding entry was created with correct key
    let embeddingEntry = vox.manifest.embeddingEntries?["qwen3-tts-0.6b-clone-prompt"]
    #expect(embeddingEntry != nil)
    #expect(embeddingEntry?.model == Qwen3TTSModelRepo.base0_6B.rawValue)
    #expect(embeddingEntry?.format == "bin")
  }

  @Test("addSampleAudio adds audio with correct path and metadata")
  func addSampleAudioToVoxFile() throws {
    let vox = VoxFile(name: "AddTest", description: "Testing addSampleAudio.")
    let audioData = Data(repeating: 0xFF, count: 200)
    try VoxExporter.addSampleAudio(to: vox, data: audioData, modelRepo: .base1_7B)

    let entry = vox[VoxExporter.sampleAudioPath(for: .base1_7B)]
    #expect(entry?.data == audioData)

    // Verify manifest embedding entry was created with correct key
    let embeddingEntry = vox.manifest.embeddingEntries?["qwen3-tts-1.7b-sample-audio"]
    #expect(embeddingEntry != nil)
    #expect(embeddingEntry?.model == Qwen3TTSModelRepo.base1_7B.rawValue)
    #expect(embeddingEntry?.format == "wav")
  }

  @Test("addClonePrompt and addSampleAudio coexist for same model")
  func addBothToVoxFile() throws {
    let vox = VoxFile(name: "BothTest", description: "Testing both entries.")
    let promptData = Data(repeating: 0xAB, count: 64)
    let audioData = Data(repeating: 0xCD, count: 128)

    try VoxExporter.addClonePrompt(to: vox, data: promptData)
    try VoxExporter.addSampleAudio(to: vox, data: audioData)

    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == promptData)
    #expect(vox[VoxExporter.sampleAudioPath(for: .base1_7B)]?.data == audioData)

    // Both embedding entries should exist with distinct keys
    #expect(vox.manifest.embeddingEntries?["qwen3-tts-1.7b-clone-prompt"] != nil)
    #expect(vox.manifest.embeddingEntries?["qwen3-tts-1.7b-sample-audio"] != nil)
  }

  @Test("addClonePrompt for multiple models preserves both in VoxFile")
  func addClonePromptMultipleModelsVoxFile() throws {
    let vox = VoxFile(name: "MultiModel", description: "Testing multi-model in VoxFile.")
    let prompt1_7B = Data(repeating: 0x17, count: 64)
    let prompt0_6B = Data(repeating: 0x06, count: 32)

    try VoxExporter.addClonePrompt(to: vox, data: prompt1_7B, modelRepo: .base1_7B)
    try VoxExporter.addClonePrompt(to: vox, data: prompt0_6B, modelRepo: .base0_6B)

    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == prompt1_7B)
    #expect(vox[VoxExporter.clonePromptPath(for: .base0_6B)]?.data == prompt0_6B)
  }

  // MARK: - URL-Based Update Operations (round-trip)

  @Test("updateClonePrompt for different models preserves both")
  func updateClonePromptMultipleModels() throws {
    let tempDir = makeTempDir()
    defer { cleanup(tempDir) }
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Create a minimal .vox file.
    let voxURL = tempDir.appendingPathComponent("multi.vox")
    let vox = VoxFile(name: "MultiModel", description: "Testing multi-model clone prompt storage.")
    try vox.write(to: voxURL)

    // Add clone prompts for two different models.
    let prompt1_7B = Data(repeating: 0x17, count: 64)
    let prompt0_6B = Data(repeating: 0x06, count: 32)
    try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: prompt1_7B, modelRepo: .base1_7B)
    try VoxExporter.updateClonePrompt(in: voxURL, clonePromptData: prompt0_6B, modelRepo: .base0_6B)

    // Both should be present.
    let readBack = try VoxFile(contentsOf: voxURL)
    #expect(readBack[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == prompt1_7B)
    #expect(readBack[VoxExporter.clonePromptPath(for: .base0_6B)]?.data == prompt0_6B)
  }

  // MARK: - Language-Aware Path Helpers

  @Test("clonePromptPath with nil language is the language-less path")
  func clonePromptPathNilLanguage() {
    #expect(
      VoxExporter.clonePromptPath(for: .base1_7B, language: nil)
        == "embeddings/qwen3-tts/1.7b/clone-prompt.bin")
  }

  @Test("clonePromptPath with a language inserts the <lang> segment")
  func clonePromptPathWithLanguage() {
    #expect(
      VoxExporter.clonePromptPath(for: .base1_7B, language: "es")
        == "embeddings/qwen3-tts/1.7b/es/clone-prompt.bin")
  }

  @Test("clonePromptPath with \"default\" resolves to the language-less path")
  func clonePromptPathDefaultLanguage() {
    #expect(
      VoxExporter.clonePromptPath(for: .base1_7B, language: "default")
        == VoxExporter.clonePromptPath(for: .base1_7B, language: nil))
  }

  @Test("sampleAudioPath language behavior mirrors clonePromptPath")
  func sampleAudioPathLanguage() {
    #expect(
      VoxExporter.sampleAudioPath(for: .base1_7B, language: nil)
        == "embeddings/qwen3-tts/1.7b/sample-audio.wav")
    #expect(
      VoxExporter.sampleAudioPath(for: .base1_7B, language: "es")
        == "embeddings/qwen3-tts/1.7b/es/sample-audio.wav")
    #expect(
      VoxExporter.sampleAudioPath(for: .base1_7B, language: "default")
        == VoxExporter.sampleAudioPath(for: .base1_7B, language: nil))
  }

  // MARK: - Language-Aware Write Operations

  @Test("addClonePrompt with a language writes the <lang> path, key, and metadata")
  func addClonePromptWithLanguage() throws {
    let vox = VoxFile(name: "LangTest", description: "Testing language-aware clone prompt.")
    let promptData = Data(repeating: 0x45, count: 96)
    try VoxExporter.addClonePrompt(to: vox, data: promptData, modelRepo: .base1_7B, language: "es")

    // Data is at the language-specific path.
    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B, language: "es")]?.data == promptData)

    // A language-distinct embedding key exists and carries the language tag.
    let entry = vox.manifest.embeddingEntries?["qwen3-tts-1.7b-es-clone-prompt"]
    #expect(entry != nil)
    #expect(entry?.language == "es")
  }

  @Test("default and per-language clone prompts coexist for the same model")
  func addClonePromptDefaultAndLanguageCoexist() throws {
    let vox = VoxFile(name: "CoexistTest", description: "Default + es must not collide.")
    let defaultData = Data(repeating: 0x01, count: 64)
    let esData = Data(repeating: 0x02, count: 64)

    try VoxExporter.addClonePrompt(to: vox, data: defaultData, modelRepo: .base1_7B)
    try VoxExporter.addClonePrompt(to: vox, data: esData, modelRepo: .base1_7B, language: "es")

    // Two distinct entries, neither overwriting the other.
    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == defaultData)
    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B, language: "es")]?.data == esData)
    #expect(vox.manifest.embeddingEntries?["qwen3-tts-1.7b-clone-prompt"] != nil)
    #expect(vox.manifest.embeddingEntries?["qwen3-tts-1.7b-es-clone-prompt"] != nil)
  }

  @Test("addClonePrompt with nil language is byte-for-byte the legacy path and key")
  func addClonePromptNilLanguageUnchanged() throws {
    let vox = VoxFile(name: "RegressionTest", description: "nil language == legacy behavior.")
    let promptData = Data(repeating: 0x33, count: 80)
    try VoxExporter.addClonePrompt(to: vox, data: promptData, modelRepo: .base1_7B, language: nil)

    // Same path and key the pre-language code produced.
    #expect(vox[VoxExporter.clonePromptPath(for: .base1_7B)]?.data == promptData)
    let entry = vox.manifest.embeddingEntries?["qwen3-tts-1.7b-clone-prompt"]
    #expect(entry != nil)
    #expect(entry?.language == nil)
  }
}
