# diga CLI Reference

`diga` is a drop-in replacement for macOS `/usr/bin/say` using on-device neural text-to-speech via Qwen3-TTS.

## Basic Usage

```bash
# Speak text
diga "Hello, world!"

# Read from file or stdin
diga -f input.txt
echo "Hello" | diga

# Write to file (WAV, AIFF, or M4A)
diga -o output.wav "Hello, world!"
```

## Voice Management

```bash
diga --voices                                          # List voices
diga -v elena "Hello"                                  # Use a voice
diga --design "warm female voice, 30s, confident" elena  # Design voice
diga --clone reference.wav elena                       # Clone voice
diga --import-vox elena.vox                            # Import .vox file
diga -v elena.vox "Hello"                              # Synthesize from .vox directly
```

## Model Selection

```bash
diga --model 0.6b "Hello"   # Smaller model (<16GB RAM)
diga --model 1.7b "Hello"   # Larger model (better quality)
```

On first run, `diga` auto-downloads the appropriate Qwen3-TTS model (~2-4 GB) from HuggingFace.

## Portable Voice Files (.vox)

VoxAlta uses the `.vox` format for portable voice identity files. A `.vox` is a ZIP archive containing:

- **Manifest** -- Voice metadata (name, description, provenance)
- **Reference audio** -- Source audio for cloned voices
- **Embeddings** -- Clone prompt (`qwen3-tts/clone-prompt.bin`) and sample audio (`qwen3-tts/sample-audio.wav`)

When you create a voice with `--design` or `--clone`, a `.vox` file is automatically exported to `~/.diga/voices/`. The CLI synthesizes a phoneme pangram, plays it through speakers so you can hear the voice immediately, and embeds the sample into the `.vox` file.

```bash
# Create a voice -- hear it immediately, .vox saved automatically
diga --design "warm male baritone, 40s" narrator

# Import a .vox from someone else
diga --import-vox narrator.vox

# Use a .vox directly without importing
diga -v narrator.vox "Hello, world!"

# Inspect a .vox file
unzip -l ~/.diga/voices/narrator.vox
```
