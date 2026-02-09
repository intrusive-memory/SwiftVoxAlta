# SwiftVoxAlta

## What It Is

SwiftVoxAlta is a privacy-first, on-device voice synthesis framework for Apple Silicon. It is a sibling to SwiftBruja (on-device LLM inference) and shares the same design philosophy: one import, minimal API surface, everything runs locally.

Where SwiftBruja takes text in and returns text out, SwiftVoxAlta takes text in and returns audio out -- with a character-aware pipeline that derives voices from script content rather than manual configuration.

## Core Premise

Given a script (Fountain format or plain text with character attribution), SwiftVoxAlta:

1. Analyzes each character's dialogue, descriptions, and stage directions
2. Synthesizes a voice profile from that textual evidence
3. Generates speech for every line, per character, with consistent voice identity
4. Exports audio (per-line WAV files, per-character tracks, or a mixed-down read)

The guiding principle is **script-derived voice creation**: the voice should emerge from what the writer wrote, not from a sound designer's interpretation layered on top. Tone directions come from parentheticals and stage directions in the script itself.

## Engine

Qwen3-TTS (Alibaba, Apache 2.0) running on MLX via mlx-audio-swift.

Three model variants, each serving a distinct role:

| Model | Parameters | Role |
|-------|-----------|------|
| Qwen3-TTS-12Hz-1.7B-VoiceDesign | 1.7B | Create voices from text descriptions |
| Qwen3-TTS-12Hz-1.7B-Base | 1.7B | Clone designed voices across all lines |
| Qwen3-TTS-12Hz-0.6B-Base | 0.6B | Lightweight cloning for draft renders |

Output: 24kHz WAV audio. Streaming latency: ~97ms first packet.

## Relationship to SwiftBruja

SwiftVoxAlta depends on SwiftBruja for the LLM analysis pass. Before any voice is generated, the script text must be analyzed to extract character profiles, summaries, and voice design instructions. SwiftBruja provides that inference capability.

Shared infrastructure:
- Model cache at `~/Library/Caches/intrusive-memory/Models/` (LLM models under `LLM/`, TTS models under `TTS/`)
- Memory management patterns (validate before load, auto-tune parameters)
- HuggingFace download pipeline
- Actor-based concurrency model
- Facade API pattern

## Audience

- Screenwriters who want to hear their scripts read by distinct character voices
- Audiobook producers working from manuscripts
- Game developers prototyping character dialogue
- Anyone building voice pipelines on Apple Silicon without cloud dependencies

## Platform Requirements

- macOS 26.0+ / iOS 26.0+ (Apple Silicon only)
- Swift 6.2+
- 8 GB RAM minimum (16 GB recommended for simultaneous VoiceDesign + Base model loading)
- ~5-8 GB disk for TTS models
