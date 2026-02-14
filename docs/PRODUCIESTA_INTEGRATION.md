# Produciesta Integration Guide

## Overview

VoxAlta integrates with Produciesta as a voice provider, offering 9 on-device CustomVoice preset speakers for podcast character voice assignment. All voices are production-ready and generate high-quality audio in real-time on Apple Silicon devices.

This integration provides a seamless experience where podcast creators can:
- Select from 9 professional voices per character
- Generate consistent voice audio for dialogue without setup
- Access voices instantly without API keys or cloud dependencies
- Maintain complete privacy with on-device inference

## Prerequisites

- **macOS 26.0+** or **iOS 26.0+** (Apple Silicon required)
- **Swift 6.2+**
- **Xcode 26+**
- SwiftVoxAlta package dependency added to Produciesta
- ~4.2 GB disk space for Qwen3-TTS-1.7B-CustomVoice model (auto-downloads on first use)

## Installation

### 1. Add Package Dependency

In Produciesta's `Package.swift`, add SwiftVoxAlta as a local package dependency:

```swift
let package = Package(
    name: "Produciesta",
    dependencies: [
        .package(path: "../SwiftVoxAlta"),
        // ... other dependencies
    ],
    targets: [
        .target(
            name: "Produciesta",
            dependencies: [
                .product(name: "SwiftVoxAlta", package: "SwiftVoxAlta"),
                // ... other dependencies
            ]
        )
    ]
)
```

### 2. Verify Build

```bash
cd ../Produciesta
xcodebuild build -scheme Produciesta -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Voice Selection Integration

### Available Voices

| Voice | Gender | Description |
|-------|--------|-------------|
| **ryan** | Male | Dynamic male voice with strong rhythmic drive |
| **aiden** | Male | Sunny American male voice with clear midrange |
| **vivian** | Female | Bright, slightly edgy young Chinese female voice |
| **serena** | Female | Warm, gentle young Chinese female voice |
| **uncle_fu** | Male | Seasoned Chinese male voice with low, mellow timbre |
| **dylan** | Male | Youthful Beijing male voice with clear timbre |
| **eric** | Male | Lively Chengdu male voice with husky brightness |
| **anna** | Female | Playful Japanese female voice with light timbre |
| **sohee** | Female | Warm Korean female voice with rich emotion |

### macOS Voice Selection UI

If Produciesta has a voice selection UI (e.g., character voice dropdown), it will automatically show VoxAlta's 9 preset speakers alongside any other configured voice providers.

Example SwiftUI implementation:

```swift
import SwiftUI
import SwiftHablare
import SwiftVoxAlta

struct VoiceSelectionView: View {
    @State private var selectedVoiceId: String = "ryan"
    @State private var availableVoices: [Voice] = []

    var body: some View {
        VStack {
            Text("Select Voice for Character")

            Picker("Voice", selection: $selectedVoiceId) {
                ForEach(availableVoices, id: \.id) { voice in
                    HStack {
                        Text(voice.name)
                        Text(voice.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(voice.id)
                }
            }
        }
        .onAppear {
            Task {
                let registry = VoiceProviderRegistry.shared
                guard let provider = registry.provider(for: "voxalta") else {
                    return
                }
                availableVoices = try await provider.fetchVoices(languageCode: "en")
            }
        }
    }
}
```

### iOS Voice Selection

For iOS apps, the voice selection UI would follow similar patterns, fetching voices from the VoxAlta provider via the VoiceProviderRegistry.

## Audio Generation

### Generating Character Dialogue

Once a voice is selected for a character, audio generation is straightforward:

```swift
import SwiftVoxAlta

let provider = VoxAltaVoiceProvider()

// Generate audio for a single line of dialogue
let audioData = try await provider.generateAudio(
    text: "Hello, I'm Ryan. This is a test of the VoxAlta voice provider.",
    voiceId: "ryan",
    languageCode: "en"
)

// Audio is returned as WAV data (24kHz, 16-bit PCM, mono)
// Ready for storage via Produciesta's SwiftData layer
```

### Processing Multiple Lines

For episodes with multiple character lines:

```swift
let provider = VoxAltaVoiceProvider()
let characterLines = [
    (character: "Ryan", text: "Hello everyone."),
    (character: "Serena", text: "Welcome to the podcast."),
    (character: "Ryan", text: "Today we're talking about AI.")
]

var audioChunks: [(characterName: String, audioData: Data)] = []

for (character, text) in characterLines {
    // Look up voice ID for this character
    guard let voiceId = characterVoiceMap[character] else { continue }

    let audio = try await provider.generateAudio(
        text: text,
        voiceId: voiceId,
        languageCode: "en"
    )

    audioChunks.append((character, audio))
}

// Store audioChunks via Produciesta's SwiftData persistence layer
```

## E2E Testing

### Basic Provider Test

Verify VoxAlta is registered and accessible:

```swift
import Testing
import SwiftHablare
import SwiftVoxAlta

@Test("VoxAlta provider registration")
func testVoxAltaRegistration() async throws {
    let registry = VoiceProviderRegistry.shared

    let provider = try #require(
        registry.provider(for: "voxalta"),
        "VoxAlta provider not registered"
    )

    let voices = try await provider.fetchVoices(languageCode: "en")
    #expect(voices.count >= 9, "Should have at least 9 preset speakers")
}
```

### Audio Generation Test

Verify audio generation works correctly:

```swift
@Test("Generate audio with preset speaker")
func testAudioGeneration() async throws {
    let provider = VoxAltaVoiceProvider()

    let audio = try await provider.generateAudio(
        text: "This is a test of VoxAlta.",
        voiceId: "ryan",
        languageCode: "en"
    )

    // Verify WAV format (RIFF header)
    let riff = String(data: audio[0..<4], encoding: .ascii)
    #expect(riff == "RIFF", "Should be WAV format")

    // Verify non-zero size
    #expect(audio.count > 44, "Audio data should be larger than WAV header")
}
```

### Voice Duration Test

Measure audio duration for timeline synchronization:

```swift
@Test("Audio duration calculation")
func testAudioDuration() async throws {
    let provider = VoxAltaVoiceProvider()

    let processed = try await provider.generateProcessedAudio(
        text: "Hello from VoxAlta.",
        voiceId: "ryan",
        languageCode: "en"
    )

    // Duration is in seconds
    #expect(processed.durationSeconds > 0.5, "Audio should have measurable duration")
    #expect(processed.durationSeconds < 10, "Short text should generate < 10 second audio")
}
```

## Performance Notes

### Model Loading (First Use)

On the first audio generation call:
- Qwen3-TTS-1.7B-CustomVoice model downloads from HuggingFace (~4.2 GB)
- Model cached at `~/Library/SharedModels/` via SwiftAcervo
- Loading takes 30-60 seconds total (download + initialization)

**Recommendation**: Pre-warm the model during app startup or initial setup:

```swift
// In app startup (e.g., SceneDelegate or @main struct)
Task {
    let provider = VoxAltaVoiceProvider()

    // Pre-warm model by generating short audio
    _ = try? await provider.generateAudio(
        text: "Ready",
        voiceId: "ryan",
        languageCode: "en"
    )
}
```

### Subsequent Generations

- Model is cached in memory after first load
- Audio generation: 2-5 seconds per line (depends on text length)
- Real-time applicable for interactive podcast recording

### Memory Requirements

- **Minimum**: 8 GB RAM (1.7B model requires ~6-7 GB)
- **Recommended**: 16+ GB RAM (allows headroom for other processes)
- **macOS automatic**: If insufficient, macOS swaps to disk (slower but functional)

## Troubleshooting

### Provider Not Registered

**Problem**: VoxAlta provider not appearing in voice selection UI

**Solution**: Verify provider registration in app startup:

```swift
let registry = VoiceProviderRegistry.shared
let provider = registry.provider(for: "voxalta")
assert(provider != nil, "VoxAlta should be registered")
```

If nil, ensure:
1. SwiftVoxAlta is imported at module setup
2. VoxAltaProviderDescriptor is registered before voice selection UI appears
3. Import order is correct (VoiceProviderRegistry before VoxAlta setup)

### Audio Generation Fails

**Problem**: `generateAudio()` throws error

**Check**:
1. Voice ID is valid (case-sensitive): `ryan`, `aiden`, `vivian`, `serena`, `uncle_fu`, `dylan`, `eric`, `anna`, `sohee`
2. Device has Apple Silicon (M1/M2/M3/M4)
3. macOS/iOS version is 26.0 or higher
4. Disk space available for model cache (~4.2 GB)

**Debug**:
```swift
do {
    let audio = try await provider.generateAudio(...)
} catch let error as VoxAltaError {
    print("VoxAlta error: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Slow Audio Generation

**Problem**: Audio generation takes >10 seconds

**Likely cause**: Model still loading from disk (first time or after app restart)

**Solution**:
1. Check system activity in Activity Monitor
2. Verify network connectivity (model download)
3. Pre-warm model on app startup (see Performance Notes)

### Model Download Fails

**Problem**: "Failed to download model" error

**Check**:
1. Internet connectivity is active
2. HuggingFace is accessible (no network restrictions)
3. Disk space available in `~/Library/SharedModels/`
4. File system permissions allow write to home directory

**Manual recovery**:
```bash
# Clear cached models and retry
rm -rf ~/Library/SharedModels/mlx-community/Qwen3-TTS*
```

## Integration with Produciesta Storage

### Storing Generated Audio

Generated audio should be stored via Produciesta's SwiftData persistence layer:

```swift
import SwiftData

@Model
final class PodcastAudioAsset {
    var characterName: String
    var voiceId: String
    var lineText: String
    var audioData: Data  // WAV format from VoxAlta
    var durationSeconds: Double
    var generatedAt: Date

    init(characterName: String, voiceId: String, lineText: String,
         audioData: Data, durationSeconds: Double) {
        self.characterName = characterName
        self.voiceId = voiceId
        self.lineText = lineText
        self.audioData = audioData
        self.durationSeconds = durationSeconds
        self.generatedAt = Date()
    }
}

// Usage
let provider = VoxAltaVoiceProvider()
let audioData = try await provider.generateAudio(
    text: "Hello everyone",
    voiceId: "ryan",
    languageCode: "en"
)

let asset = PodcastAudioAsset(
    characterName: "Ryan",
    voiceId: "ryan",
    lineText: "Hello everyone",
    audioData: audioData,
    durationSeconds: 1.5
)

// Insert into SwiftData context
```

## Privacy & Security

- **No cloud dependencies** -- All TTS inference runs locally on device
- **No API keys required** -- Works offline after model download
- **No telemetry** -- VoxAlta does not send usage data
- **User data stays local** -- Audio is never uploaded to external services
- **GDPR compliant** -- No personal data collection

## Limitations

- **Apple Silicon only** -- Qwen3-TTS requires Metal GPU support (M1/M2/M3/M4)
- **macOS 26+ / iOS 26+** -- Older OS versions not supported
- **Offline after initial setup** -- Model download required once, subsequent use works offline
- **Single model in memory** -- Only one TTS model loaded at a time
- **Voice consistency** -- Each voice ID should map to same character for consistency

## Support & Feedback

For issues or feature requests:
- File an issue on [SwiftVoxAlta GitHub](https://github.com/intrusive-memory/SwiftVoxAlta)
- Check [AGENTS.md](../AGENTS.md) for detailed API documentation
- Review [Available Voices](AVAILABLE_VOICES.md) for voice characteristics

## Next Steps

1. ✅ Add SwiftVoxAlta dependency to Produciesta
2. ✅ Import VoxAlta in your app's main module
3. ✅ Test voice fetching with test code above
4. ✅ Integrate into voice selection UI
5. ✅ Store generated audio via SwiftData
6. ✅ Run E2E tests to verify end-to-end workflow
7. ✅ Deploy and gather user feedback

---

**Version**: 1.0
**Last Updated**: February 2026
**SwiftVoxAlta Version**: 0.2.0+
