# Available Voices

This document lists all voices available in SwiftVoxAlta and the `diga` CLI.

**Current Version**: 0.2.1

---

## Voice Types

SwiftVoxAlta supports four types of voices:

| Type | Description | Model Used | Clone Prompt Required |
|------|-------------|------------|----------------------|
| **Preset** | Professional voices from Qwen3-TTS CustomVoice | CustomVoice (0.6B or 1.7B) | No (speaker name only) |
| **Designed** | Custom voices created from text descriptions | VoiceDesign (1.7B) | Yes (generated from description) |
| **Cloned** | Voices cloned from reference audio files | Base (0.6B or 1.7B) | Yes (extracted from audio) |
| **Builtin** | Legacy voice type (deprecated) | N/A | N/A |

---

## Built-in Preset Voices

These voices are shipped with `diga` and require no setup. They use Qwen3-TTS CustomVoice preset speakers.

### English Speakers

| Voice Name | Speaker ID | Description | Gender | Language | Canonical URI |
|------------|------------|-------------|--------|----------|---------------|
| `ryan` | `ryan` | Dynamic male voice with strong rhythmic drive | Male | English | `voxalta://ryan?lang=en` |
| `aiden` | `aiden` | Sunny American male voice with clear midrange | Male | English (US) | `voxalta://aiden?lang=en` |

### Chinese Speakers

| Voice Name | Speaker ID | Description | Gender | Language | Canonical URI |
|------------|------------|-------------|--------|----------|---------------|
| `vivian` | `vivian` | Bright, slightly edgy young female voice | Female | Chinese | `voxalta://vivian?lang=zh` |
| `serena` | `serena` | Warm, gentle young female voice | Female | Chinese | `voxalta://serena?lang=zh` |
| `uncle_fu` | `uncle_fu` | Seasoned male voice with low, mellow timbre | Male | Chinese | `voxalta://uncle_fu?lang=zh` |
| `dylan` | `dylan` | Youthful Beijing male voice with clear timbre | Male | Chinese (Beijing) | `voxalta://dylan?lang=zh` |
| `eric` | `eric` | Lively Chengdu male voice with husky brightness | Male | Chinese (Chengdu) | `voxalta://eric?lang=zh` |

### Japanese Speakers

| Voice Name | Speaker ID | Description | Gender | Language | Canonical URI |
|------------|------------|-------------|--------|----------|---------------|
| `anna` | `ono_anna` | Playful female voice with light timbre | Female | Japanese | `voxalta://anna?lang=ja` |

### Korean Speakers

| Voice Name | Speaker ID | Description | Gender | Language | Canonical URI |
|------------|------------|-------------|--------|----------|---------------|
| `sohee` | `sohee` | Warm female voice with rich emotion | Female | Korean | `voxalta://sohee?lang=ko` |

---

## Using Preset Voices

### CLI Usage

```bash
# List all voices (including presets)
diga --voices
diga -v ?

# Use a preset voice
diga -v ryan "Hello, world!"
diga -v vivian "你好，世界！"
diga -v anna "こんにちは、世界！"
diga -v sohee "안녕하세요, 세계!"

# Write to file with a preset voice
diga -v aiden -o output.m4a "Hello from VoxAlta!"
```

### Library Usage

Preset voices are available through the VoxAlta VoiceProvider when using CustomVoice models:

```swift
import SwiftVoxAlta

// CustomVoice preset voices are accessed via the speaker name
let audioData = try await provider.generateAudio(
    text: "Hello, world!",
    voiceId: "ryan",  // Uses CustomVoice speaker "ryan"
    languageCode: "en"
)
```

### Voice Casting with URIs

Use canonical VoiceURIs for voice casting in SwiftHablare:

```swift
import SwiftHablare
import SwiftCompartido

// Create VoiceURI for a preset voice
let voiceURI = VoiceURI(uriString: "voxalta://ryan?lang=en")!

// Assign to character in SwiftCompartido
let mapping = CharacterVoiceMapping(
    characterName: "NARRATOR",
    voiceURI: voiceURI
)

// Generate audio via GenerationService
let voice = try await voiceURI.resolve(using: service)
let audioData = try await service.generateAudio(
    text: "Hello from VoxAlta!",
    voice: voice
)
```

---

## Creating Custom Voices

### Designed Voices (from text description)

Create a new voice from a text description using VoiceDesign:

```bash
# CLI
diga --design "warm female voice, 30s, confident and professional" elena

# Use the newly created voice
diga -v elena "Hello from VoxAlta!"
```

**Library Usage**:

```swift
import SwiftVoxAlta

// Generate voice candidates from character profile
let candidates = try await VoiceDesigner.generateCandidates(profile: profile)

// Lock the selected candidate
let lock = VoiceLock(
    characterName: "ELENA",
    clonePromptData: candidates[0].clonePromptData,
    designInstruction: candidates[0].designDescription
)

// Load into provider
await provider.loadVoice(
    id: "ELENA",
    clonePromptData: lock.clonePromptData,
    gender: "female"
)
```

**Canonical URI for designed voices**:

After creating a designed voice, its canonical URI is:

```
voxalta://ELENA?lang=en
```

Where `ELENA` is the voice name (case-sensitive) and `en` is the language code.

### Cloned Voices (from reference audio)

Clone a voice from a reference audio file:

```bash
# CLI
diga --clone reference.wav elena

# Use the cloned voice
diga -v elena "Hello from VoxAlta!"
```

**Requirements for reference audio**:
- Format: WAV, MP3, M4A, or AIFF
- Duration: 3-10 seconds recommended (clean speech)
- Quality: Clear speech with minimal background noise
- Content: Single speaker, natural speech (not shouting/whispering)

**Library Usage**:

```swift
import SwiftVoxAlta

// Extract clone prompt from reference audio
let clonePromptData = try await modelManager.extractClonePrompt(
    from: audioData,
    modelSize: .base1_7B
)

// Load into provider
await provider.loadVoice(
    id: "ELENA",
    clonePromptData: clonePromptData,
    gender: "female"
)
```

**Canonical URI for cloned voices**:

After cloning a voice, its canonical URI is:

```
voxalta://elena?lang=en
```

Where `elena` is the voice name (case-sensitive) and `en` is the language code.

---

## Voice URI Format

VoxAlta voices use the standard VoiceURI format from SwiftHablare:

```
voxalta://<voiceId>?lang=<languageCode>
```

### Components

| Component | Description | Required | Example |
|-----------|-------------|----------|---------|
| `voxalta` | Provider ID (always lowercase) | Yes | `voxalta` |
| `voiceId` | Voice name (case-sensitive) | Yes | `ryan`, `ELENA`, `elena` |
| `languageCode` | ISO 639-1 language code | Optional | `en`, `zh`, `ja`, `ko` |

### Examples

```swift
// Preset voices
let ryanURI = VoiceURI(uriString: "voxalta://ryan?lang=en")!
let vivianURI = VoiceURI(uriString: "voxalta://vivian?lang=zh")!
let annaURI = VoiceURI(uriString: "voxalta://anna?lang=ja")!

// Custom voices (designed or cloned)
let elenaURI = VoiceURI(uriString: "voxalta://ELENA?lang=en")!
let marcusURI = VoiceURI(uriString: "voxalta://marcus?lang=en")!

// Voice URI without language (uses system default)
let defaultURI = VoiceURI(uriString: "voxalta://ryan")!
```

### Programmatic URI Creation

```swift
import SwiftHablare

// From components
let uri = VoiceURI(
    providerId: "voxalta",
    voiceId: "ryan",
    languageCode: "en"
)

// From Voice model
let voice = Voice(
    id: "ryan",
    name: "Ryan",
    language: "en",
    providerId: "voxalta"
)
let uri2 = VoiceURI(from: voice)

// Convert to string
print(uri.uriString)  // "voxalta://ryan?lang=en"
```

### Using URIs for Voice Casting

```swift
import SwiftHablare
import SwiftCompartido

// Create character-to-voice mapping
let mapping = CharacterVoiceMapping(
    characterName: "NARRATOR",
    voiceURI: VoiceURI(uriString: "voxalta://ryan?lang=en")!
)

// Resolve URI to Voice
let service = GenerationService.shared
let voice = try await mapping.voiceURI.resolve(using: service)

// Generate audio
let audioData = try await service.generateAudio(
    text: "Once upon a time...",
    voice: voice
)
```

---

## Voice Storage

### CLI Voice Store

Custom voices (designed and cloned) are stored at:

```
~/.diga/voices/
├── index.json              # Voice index (metadata)
├── elena.cloneprompt       # Clone prompt data (binary)
└── marcus.cloneprompt      # Another voice
```

**Index format** (`index.json`):

```json
[
  {
    "name": "elena",
    "type": "designed",
    "designDescription": "warm female voice, 30s, confident",
    "clonePromptPath": "elena.cloneprompt",
    "createdAt": "2024-03-15T10:30:00Z"
  },
  {
    "name": "marcus",
    "type": "cloned",
    "designDescription": null,
    "clonePromptPath": "marcus.cloneprompt",
    "createdAt": "2024-03-15T11:45:00Z"
  }
]
```

### Library Voice Cache

The VoxAltaVoiceProvider caches loaded voices in memory via `VoxAltaVoiceCache` (actor):

```swift
// Load voice into cache (done once)
await provider.loadVoice(
    id: "ELENA",
    clonePromptData: lockData,
    gender: "female"
)

// Subsequent calls use cached clone prompt
let audio1 = try await provider.generateAudio(text: "Hello!", voiceId: "ELENA", languageCode: "en")
let audio2 = try await provider.generateAudio(text: "Goodbye!", voiceId: "ELENA", languageCode: "en")
```

---

## Voice Management

### Listing Voices

```bash
# CLI
diga --voices
diga -v ?
```

Output format:

```
Available voices:
  ryan      [preset]  Dynamic male voice with strong rhythmic drive
  aiden     [preset]  Sunny American male voice with clear midrange
  elena     [designed] warm female voice, 30s, confident
  marcus    [cloned]
```

### Deleting Voices

Preset voices cannot be deleted. Custom voices can be removed:

```bash
# Remove voice from store (removes index entry + clone prompt file)
rm ~/.diga/voices/elena.cloneprompt
# Then manually edit ~/.diga/voices/index.json to remove the entry
```

---

## Model Requirements

### VoiceDesign (Designed Voices)

- **Model**: `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`
- **Size**: ~4.2 GB
- **RAM**: 16+ GB recommended
- **Purpose**: Generate voices from text descriptions

### Base (Cloned Voices)

- **Model (recommended)**: `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`
- **Size**: ~4.3 GB
- **RAM**: 16+ GB recommended
- **Model (lighter)**: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16`
- **Size**: ~2.4 GB
- **RAM**: 8+ GB
- **Purpose**: Clone voices from reference audio

### CustomVoice (Preset Voices)

- **Model (recommended)**: `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16`
- **Size**: ~4.3 GB
- **RAM**: 16+ GB recommended
- **Model (lighter)**: `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16`
- **Size**: ~2.4 GB
- **RAM**: 8+ GB
- **Purpose**: Use professional preset speakers

**Note**: `diga` auto-selects 1.7B models on systems with ≥16 GB RAM, otherwise 0.6B.

---

## Language Support

| Language | Supported | Preset Voices Available |
|----------|-----------|------------------------|
| English | ✅ Yes | ryan, aiden |
| Chinese (Mandarin) | ✅ Yes | vivian, serena, uncle_fu, dylan, eric |
| Japanese | ✅ Yes | anna |
| Korean | ✅ Yes | sohee |

**Custom voices** (designed/cloned) can be created for any language supported by Qwen3-TTS.

---

## Audio Output Format

All voices generate audio with the following characteristics:

- **Sample Rate**: 24 kHz
- **Bit Depth**: 16-bit PCM
- **Channels**: Mono
- **Format**: WAV (library), WAV/AIFF/M4A (CLI via `--file-format` or output extension)

---

## Troubleshooting

### Voice Not Found

```
Error: Voice 'xyz' not found. Use --voices to list available voices.
```

**Solution**: List voices with `diga --voices` and verify the voice name is correct.

### Model Download Issues

```
Error: Failed to download model: mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16
```

**Solution**:
- Check internet connection
- Verify HuggingFace is accessible
- Ensure sufficient disk space (~5 GB per model)
- Models cache at `~/Library/SharedModels/`

### Insufficient Memory

```
Warning: Insufficient memory for Qwen3-TTS 1.7B (available: 8.2 GB, required: 16 GB)
```

**Solution**: `diga` will automatically use 0.6B models on low-memory systems. This is a warning, not an error.

### Poor Voice Quality

**For cloned voices**:
- Ensure reference audio is 3-10 seconds of clear speech
- Avoid background noise, music, or multiple speakers
- Use high-quality recordings (not compressed/distorted)

**For designed voices**:
- Provide detailed descriptions (age, gender, accent, personality)
- Experiment with multiple candidates
- Some descriptions may not generate as expected (try rewording)

---

## See Also

- [CLI Documentation](../AGENTS.md#cli-tool-diga) - Full CLI usage and flags
- [Voice Design Pipeline](../AGENTS.md#voice-design-pipeline) - How character voices are created
- [API Usage](../AGENTS.md#api-usage) - Library integration examples
- [Qwen3-TTS Models](../AGENTS.md#qwen3-tts-models) - Model details and download info
