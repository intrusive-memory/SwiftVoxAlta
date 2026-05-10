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

## Generation Tuning

### `--chunk-target-duration <seconds>`

Target maximum estimated audio duration per TTS chunk. Long inputs are split at sentence boundaries (Foundation's ICU segmenter) into chunks no longer than this value, then synthesized sequentially and concatenated with a short silence between chunks.

- Lower values (e.g. `8`) produce stronger prosody anchors for ICL voice cloning at the cost of more inter-chunk pauses.
- The default — `12.0` seconds — is the ICL stability sweet spot.
- Higher values (e.g. `20`) reduce pauses further at the cost of weaker anchoring on long generations.

```bash
# Default: chunkTargetDuration = 12.0s
diga -v elena "A long paragraph that gets split automatically..."

# Tighter chunks for stronger anchors on a difficult ICL voice
diga -v elena --chunk-target-duration 8 "A long paragraph..."

# Looser chunks if you're willing to trade anchor strength for fewer pauses
diga -v elena --chunk-target-duration 20 "A long paragraph..."
```

The flag value must be greater than `0`. To pass a value that begins with `-` (e.g. an explicit negative, which the parser will then reject at validation), use the `=` form:

```bash
diga --chunk-target-duration=-5 "Hello"   # Errors: must be greater than 0.
```

The same handle is exposed in the library API as `GenerationSettings.chunkTargetDuration`. See [AGENTS.md → Auto-Sentence Chunking](../AGENTS.md#auto-sentence-chunking) for the full contract across CustomVoice and ICL paths.

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
