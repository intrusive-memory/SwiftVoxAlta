# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For detailed project documentation, architecture, and development guidelines, see **[AGENTS.md](AGENTS.md)**.

## Quick Reference

**Project**: SwiftVoxAlta - On-device voice design and cloning for screenplay characters

**Version**: 0.2.0

**Platforms**: iOS 26.0+, macOS 26.0+ (Apple Silicon only)

**Purpose**: VoiceProvider library for SwiftHablare using Qwen3-TTS for character-driven voice design.

## Key Components

- **VoiceProvider implementation** - text + voiceId -> audio Data via Qwen3-TTS
- **Voice design API** - character evidence -> CharacterProfile -> voice candidates -> locked voice
- **`diga` CLI** - drop-in replacement for `/usr/bin/say` with neural TTS
- **Auto-registration** - VoiceProviderDescriptor for SwiftHablare registry

## Important Notes

- **Apple Silicon only** - Qwen3-TTS requires Metal/MLX (NO Intel support)
- **ONLY supports iOS 26.0+ and macOS 26.0+** (NEVER add code for older platforms)
- **NEVER add `@available` attributes** for versions below iOS 26/macOS 26
- **MUST build with `xcodebuild`** (Metal shaders required, `swift build` won't work)
- **Use Makefile targets** for builds: `make build`, `make release`, `make test`
- **Experimental status** - APIs in active development, subject to change

## What Belongs Here

- VoiceProvider protocol implementation
- Character analysis and voice design
- Clone prompt generation and locking
- Qwen3-TTS audio synthesis
- CLI tool for voice management

## What Doesn't Belong

- Fountain parsing (SwiftCompartido)
- Voice selection UI (app layer)
- Audio storage (Produciesta/SwiftData)
- Streaming playback (SwiftHablare)

See [AGENTS.md](AGENTS.md) for complete documentation, voice design pipeline, CLI commands, and integration patterns.
