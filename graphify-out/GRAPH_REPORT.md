# Graph Report - .  (2026-07-02)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1010 nodes · 1587 edges · 63 communities (40 shown, 23 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 94 edges (avg confidence: 0.78)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e74d4642`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Audio File Writer|Audio File Writer]]
- [[_COMMUNITY_Audio Format Conversion|Audio Format Conversion]]
- [[_COMMUNITY_Telemetry & Contract Tests|Telemetry & Contract Tests]]
- [[_COMMUNITY_Vox File Export|Vox File Export]]
- [[_COMMUNITY_Codable Generation Context|Codable Generation Context]]
- [[_COMMUNITY_Audio Writer Tests|Audio Writer Tests]]
- [[_COMMUNITY_Diga Synthesis Engine|Diga Synthesis Engine]]
- [[_COMMUNITY_CLI Flag Parsing Tests|CLI Flag Parsing Tests]]
- [[_COMMUNITY_Diga Engine Tests|Diga Engine Tests]]
- [[_COMMUNITY_Voice Lock Chunking Tests|Voice Lock Chunking Tests]]
- [[_COMMUNITY_Diga CLI Command|Diga CLI Command]]
- [[_COMMUNITY_Audio Playback Tests|Audio Playback Tests]]
- [[_COMMUNITY_Apple Silicon Detection|Apple Silicon Detection]]
- [[_COMMUNITY_Voice Store Tests|Voice Store Tests]]
- [[_COMMUNITY_Vox Importer Tests|Vox Importer Tests]]
- [[_COMMUNITY_Agent Documentation|Agent Documentation]]
- [[_COMMUNITY_Generation Context Tests|Generation Context Tests]]
- [[_COMMUNITY_Model Manager Types|Model Manager Types]]
- [[_COMMUNITY_Acervo Test Environment Trait|Acervo Test Environment Trait]]
- [[_COMMUNITY_Voice Store|Voice Store]]
- [[_COMMUNITY_Release & Homebrew Tests|Release & Homebrew Tests]]
- [[_COMMUNITY_Voice Provider Audio Generation|Voice Provider Audio Generation]]
- [[_COMMUNITY_Voice Cache|Voice Cache]]
- [[_COMMUNITY_Vox Voice Provider|Vox Voice Provider]]
- [[_COMMUNITY_Voice Cache Tests|Voice Cache Tests]]
- [[_COMMUNITY_Audio Playback Buffers|Audio Playback Buffers]]
- [[_COMMUNITY_Voice Provider Tests|Voice Provider Tests]]
- [[_COMMUNITY_Telemetry Types|Telemetry Types]]
- [[_COMMUNITY_Round-Trip Consistency Tests|Round-Trip Consistency Tests]]
- [[_COMMUNITY_Async Chunk Playback|Async Chunk Playback]]
- [[_COMMUNITY_VoxAlta Error Types|VoxAlta Error Types]]
- [[_COMMUNITY_VoxAlta Error Tests|VoxAlta Error Tests]]
- [[_COMMUNITY_Vox Importer|Vox Importer]]
- [[_COMMUNITY_Error Path Tests|Error Path Tests]]
- [[_COMMUNITY_Diga Vox Integration Tests|Diga Vox Integration Tests]]
- [[_COMMUNITY_Telemetry Events|Telemetry Events]]
- [[_COMMUNITY_Voice Configuration View|Voice Configuration View]]
- [[_COMMUNITY_ComponentDescriptor Audit Docs|ComponentDescriptor Audit Docs]]
- [[_COMMUNITY_Audio Playback & Telemetry|Audio Playback & Telemetry]]
- [[_COMMUNITY_Generation Settings|Generation Settings]]
- [[_COMMUNITY_Process Memory Utility|Process Memory Utility]]
- [[_COMMUNITY_Model Memory Estimation Tests|Model Memory Estimation Tests]]
- [[_COMMUNITY_Builtin Voices|Builtin Voices]]
- [[_COMMUNITY_Diga Version Tests|Diga Version Tests]]
- [[_COMMUNITY_ComponentDescriptor Registration Tests|ComponentDescriptor Registration Tests]]
- [[_COMMUNITY_Voice Lock Codable Tests|Voice Lock Codable Tests]]
- [[_COMMUNITY_Voice Provider Metadata Tests|Voice Provider Metadata Tests]]
- [[_COMMUNITY_Telemetry Mission Docs|Telemetry Mission Docs]]
- [[_COMMUNITY_Preflight Leak Probe Tests|Preflight Leak Probe Tests]]
- [[_COMMUNITY_Vox Provider Descriptor|Vox Provider Descriptor]]
- [[_COMMUNITY_Voice Provider Duration Tests|Voice Provider Duration Tests]]
- [[_COMMUNITY_Homebrew Formula|Homebrew Formula]]
- [[_COMMUNITY_Model Manager Single-Flight Tests|Model Manager Single-Flight Tests]]
- [[_COMMUNITY_Set Telemetry Tests|Set Telemetry Tests]]
- [[_COMMUNITY_Voice Provider Error Path Tests|Voice Provider Error Path Tests]]
- [[_COMMUNITY_Diga Version|Diga Version]]
- [[_COMMUNITY_Sentence Chunking Design|Sentence Chunking Design]]
- [[_COMMUNITY_Telemetry Reporter Setter|Telemetry Reporter Setter]]
- [[_COMMUNITY_CLI Entry Point|CLI Entry Point]]
- [[_COMMUNITY_Package Manifest|Package Manifest]]
- [[_COMMUNITY_Community 62|Community 62]]

## God Nodes (most connected - your core abstractions)
1. `VoxAltaVoiceProvider` - 52 edges
2. `VoxAltaModelManager` - 29 edges
3. `VoiceLockManagerChunkingTests` - 28 edges
4. `AppleSiliconGeneration` - 27 edges
5. `GenerationContextTests` - 23 edges
6. `VoxExporterTests` - 23 edges
7. `VoxFile` - 21 edges
8. `VoxImporterTests` - 21 edges
9. `TTSLanguage` - 21 edges
10. `DigaReleaseTests` - 18 edges

## Surprising Connections (you probably didn't know these)
- `SwiftVoxAlta README` --references--> `SwiftVoxAlta Logo (retro singing mouth, JPG)`  [EXTRACTED]
  README.md → swift-vox-alta.jpg
- `StubSpeechGenerationModel` --inherits--> `SpeechGenerationModel`  [EXTRACTED]
  Tests/SwiftVoxAltaTests/Telemetry/LoadUnloadTelemetryTests.swift → Sources/SwiftVoxAlta/VoxAltaModelManager.swift
- `Changelog (Stub)` --references--> `SwiftVoxAlta AGENTS Documentation`  [EXTRACTED]
  CHANGELOG.md → AGENTS.md
- `Claude Code Instructions` --references--> `SwiftVoxAlta AGENTS Documentation`  [EXTRACTED]
  CLAUDE.md → AGENTS.md
- `Gemini Instructions` --references--> `SwiftVoxAlta AGENTS Documentation`  [EXTRACTED]
  GEMINI.md → AGENTS.md

## Import Cycles
- None detected.

## Communities (63 total, 23 thin omitted)

### Community 0 - "Audio File Writer"
Cohesion: 0.07
Nodes (31): CaseIterable, AudioFormat, aiff, m4a, wav, MLXRetentionReport, Set, Double (+23 more)

### Community 1 - "Audio Format Conversion"
Cohesion: 0.06
Nodes (40): AsyncStream, AVAudioFormat, CheckedContinuation, AudioFileWriter, AudioFileWriterError, conversionFailed, invalidWAVData, writeFailed (+32 more)

### Community 2 - "Telemetry & Contract Tests"
Cohesion: 0.06
Nodes (11): Data, Int, Int16, MLXArray, T, AudioConversion, BuildWAVDataTests, EdgeCaseTests (+3 more)

### Community 3 - "Vox File Export"
Cohesion: 0.07
Nodes (41): SwiftAcervo Usage Audit, AudioConversion, DigaEngine, SwiftVoxAlta AGENTS Documentation, GenerationContext, GenerationSettings, mlx-audio-swift, Produciesta (+33 more)

### Community 4 - "Codable Generation Context"
Cohesion: 0.06
Nodes (17): AsyncThrowingStream, AudioGeneration, GenerateParameters, VoxAltaTelemetryReporter, EndToEndContractTests, LoadUnloadTelemetryTests, StubSpeechGenerationModel, MLXRetentionTests (+9 more)

### Community 5 - "Audio Writer Tests"
Cohesion: 0.12
Nodes (8): Data, Qwen3TTSModelRepo, String, URL, VoxExporter, VoxExporterTests, URL, VoxFile

### Community 6 - "Diga Synthesis Engine"
Cohesion: 0.13
Nodes (24): DigaEngine, DigaEngineError, modelNotAvailable, synthesisFailed, voiceDesignFailed, voiceNotFound, wavConcatenationFailed, WAVConcatenator (+16 more)

### Community 7 - "CLI Flag Parsing Tests"
Cohesion: 0.09
Nodes (10): AudioFileWriterAIFFOutputTests, AudioFileWriterErrorDescriptionTests, AudioFileWriterErrorTests, AudioFileWriterM4AOutputTests, AudioFileWriterWAVOutputTests, AudioFormatEnumTests, AudioFormatInferenceTests, Data (+2 more)

### Community 8 - "Diga Engine Tests"
Cohesion: 0.06
Nodes (6): CLIChunkTargetDurationTests, CLICombinedFlagTests, CLIFileInputTests, CLIIntegrationVerificationTests, CLIModelFlagTests, CLIVoiceFlagTests

### Community 9 - "Voice Lock Chunking Tests"
Cohesion: 0.10
Nodes (10): DigaEngine, DigaEngineErrorTests, DigaEngineInstantiationTests, DigaEngineVoiceResolutionTests, WAVConcatenatorBuildTests, WAVConcatenatorTests, Data, Int (+2 more)

### Community 10 - "Diga CLI Command"
Cohesion: 0.07
Nodes (16): Locale, TTSLanguage, auto, beijingDialect, chinese, english, french, german (+8 more)

### Community 12 - "Apple Silicon Detection"
Cohesion: 0.13
Nodes (11): AsyncParsableCommand, DigaCommand, DigaBinaryIntegrationTests, ProcessResult, Int32, Bool, String, TimeInterval (+3 more)

### Community 13 - "Voice Store Tests"
Cohesion: 0.11
Nodes (8): AudioPlaybackErrorTests, AudioPlaybackPCMBufferTests, AudioPlaybackStreamingTests, DigaCommandInputRoutingTests, WAVHeaderParserTests, Data, Int, Int16

### Community 14 - "Vox Importer Tests"
Cohesion: 0.08
Nodes (24): DeviceCapability, Bool, AppleSiliconGeneration, m1, m1Max, m1Pro, m1Ultra, m2 (+16 more)

### Community 15 - "Agent Documentation"
Cohesion: 0.14
Nodes (5): BuiltinVoicesTests, CLIVoiceListingTests, StoredVoiceCodableTests, VoiceStoreTests, VoiceStore

### Community 16 - "Generation Context Tests"
Cohesion: 0.25
Nodes (5): VoxImporterTests, Bool, Data, String, URL

### Community 18 - "Acervo Test Environment Trait"
Cohesion: 0.16
Nodes (16): MLXArray, Data, Double, GenerationContext, GenerationSettings, Int, MLXArray, Qwen3TTSModelRepo (+8 more)

### Community 19 - "Voice Store"
Cohesion: 0.15
Nodes (8): GenerationSettings, Qwen3TTSModelRepo, VoxAltaModelManager, VoxAltaVoiceCache, VoxAltaVoiceProvider, VoxAltaVoiceProviderMetadataTests, VoxAltaVoiceProviderVoiceTests, VoiceProvider

### Community 20 - "Release & Homebrew Tests"
Cohesion: 0.12
Nodes (14): AcervoEnvironmentTrait, Trait, SuiteTrait, AcervoEnvironmentTrait, Trait, Bool, Self, Sendable (+6 more)

### Community 21 - "Voice Provider Audio Generation"
Cohesion: 0.19
Nodes (10): StoredVoice, VoiceStore, VoiceType, builtin, cloned, designed, preset, Bool (+2 more)

### Community 23 - "Vox Voice Provider"
Cohesion: 0.21
Nodes (7): Data, Int, String, CachedVoice, VoxAltaVoiceCache, VoiceCacheTelemetry, VoiceClonePrompt

### Community 24 - "Voice Cache Tests"
Cohesion: 0.12
Nodes (4): VoxAltaVoiceCacheCachedVoiceTests, VoxAltaVoiceCacheQueryTests, VoxAltaVoiceCacheRemoveTests, VoxAltaVoiceCacheStorageTests

### Community 25 - "Audio Playback Buffers"
Cohesion: 0.18
Nodes (10): Decoder, Encoder, Int, String, AnyCodableValue, bool, double, int (+2 more)

### Community 26 - "Voice Provider Tests"
Cohesion: 0.13
Nodes (3): VoxAltaProviderDescriptorTests, VoxAltaVoiceProviderConfigTests, VoxAltaVoiceProviderWAVDurationTests

### Community 27 - "Telemetry Types"
Cohesion: 0.23
Nodes (7): ProcessedAudio, Data, GenerationContext, String, TimeInterval, TTSLanguage, Voice

### Community 28 - "Round-Trip Consistency Tests"
Cohesion: 0.32
Nodes (8): Equatable, Double, Int, String, MLXRetentionReport, TopVoice, VoiceCacheTelemetry, TopVoice

### Community 29 - "Async Chunk Playback"
Cohesion: 0.21
Nodes (9): Sendable, Data, Date, String, URL, VoxImporter, VoxImportResult, VoxAltaTelemetryReporter (+1 more)

### Community 32 - "Vox Importer"
Cohesion: 0.33
Nodes (5): AnyView, Bool, Bool, Void, Void

### Community 33 - "Error Path Tests"
Cohesion: 0.33
Nodes (7): Codable, Int, AudioOutputFormat, aiff, m4a, wav, VoxAltaConfig

### Community 36 - "Voice Configuration View"
Cohesion: 0.25
Nodes (7): VoxAltaTelemetryEvent, metalBufferState, modelLoadComplete, modelLoadStart, modelUnloadComplete, modelUnloadStart, voiceCacheGrowth

### Community 37 - "ComponentDescriptor Audit Docs"
Cohesion: 0.38
Nodes (7): SwiftVoxAlta ComponentDescriptor Audit Report, Execution Plan: Infrastructure Adoption, Execution Plan: Reference Implementation Audit, ComponentDescriptor Pattern Reference for Other Libraries, Requirements: SwiftTubería Integration, SwiftVoxAlta Acervo Integration Requirements (Reference), SwiftVoxAlta Acervo Integration Requirements

### Community 38 - "Audio Playback & Telemetry"
Cohesion: 0.48
Nodes (5): Float, Bool, Int, TimeInterval, GenerationSettings

### Community 39 - "Generation Settings"
Cohesion: 0.38
Nodes (3): Double, VoxAltaTelemetryEvent, VoxAltaTelemetryEvent

### Community 41 - "Model Memory Estimation Tests"
Cohesion: 0.47
Nodes (3): BuiltinVoices, StoredVoice, String

### Community 43 - "Diga Version Tests"
Cohesion: 0.53
Nodes (4): Data, Date, String, VoiceLock

### Community 47 - "Telemetry Mission Docs"
Cohesion: 0.70
Nodes (5): Execution Plan: Telemetry Instrumentation, Preflight Leak Probe Result, Operation Leaking Stethoscope Iteration 01 Brief, SwiftVoxAlta Telemetry Requirements, Supervisor State: Operation Leaking Stethoscope

### Community 49 - "Vox Provider Descriptor"
Cohesion: 0.40
Nodes (3): VoxAltaModelManager, VoxAltaProviderDescriptor, VoiceProviderDescriptor

### Community 51 - "Homebrew Formula"
Cohesion: 0.50
Nodes (4): SwiftEchada, vox-format, VoxExporter, VoxImporter

## Knowledge Gaps
- **163 isolated node(s):** `wav`, `aiff`, `m4a`, `AVAudioPCMBuffer`, `playbackFailed` (+158 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **23 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `VoxAltaVoiceProvider` connect `Voice Store` to `Vox Importer`, `Codable Generation Context`, `Generation Settings`, `Vox Provider Descriptor`, `Voice Provider Duration Tests`, `Voice Provider Error Path Tests`, `Diga Version`, `Sentence Chunking Design`, `Voice Provider Tests`, `Telemetry Types`, `Async Chunk Playback`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Why does `VoxFile` connect `Audio Writer Tests` to `Generation Context Tests`, `Telemetry Events`, `Async Chunk Playback`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Why does `VoxExporter` connect `Audio Writer Tests` to `Async Chunk Playback`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Are the 26 inferred relationships involving `VoxAltaVoiceProvider` (e.g. with `.descriptor()` and `.generateAudioEmptyVoiceId()`) actually correct?**
  _`VoxAltaVoiceProvider` has 26 INFERRED edges - model-reasoned connections that need verification._
- **What connects `wav`, `aiff`, `m4a` to the rest of the system?**
  _163 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Audio File Writer` be split into smaller, more focused modules?**
  _Cohesion score 0.06766917293233082 - nodes in this community are weakly interconnected._
- **Should `Audio Format Conversion` be split into smaller, more focused modules?**
  _Cohesion score 0.06127946127946128 - nodes in this community are weakly interconnected._