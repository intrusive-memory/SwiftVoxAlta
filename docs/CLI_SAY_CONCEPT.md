# `diga` — On-Device Neural TTS CLI for macOS

> Concept doc for a macOS command-line utility that replaces Apple's `say` command
> with Qwen3-TTS inference via mlx-audio-swift. On deck — not part of current sprint work.

## Goal

Drop-in replacement for `/usr/bin/say` that routes through Qwen3-TTS running locally
on Apple Silicon, producing higher-quality neural speech while preserving the familiar
CLI interface macOS users and scripts already depend on.

Distributed via `brew tap intrusive-memory/tap && brew install diga`.
Standard emotion/pacing for all output in v1 — no tuning knobs.

---

## CLI Interface (v1)

### Synopsis

```
diga [-v voice] [-o outfile] [-f file | string ...]
diga --voices                  # list available voices
diga --design "description"    # design a new voice from text description
diga --clone ref.wav name      # clone a voice from reference audio
diga --version                 # print version and exit
```

### Flags

| Flag | Purpose |
|------|---------|
| `string ...` | Text to speak (multiple args joined by spaces) |
| `-v voice` | Voice name. `?` lists available voices. Default: built-in neutral voice. |
| `-o file` | Write audio to file instead of playing. Format inferred from extension. |
| `-f file` | Read text from file. `-` for stdin. |
| `--file-format` | Output format: `wav` (default), `aiff`, `m4a` |
| `--voices` | List all available voices (built-in + custom) |
| `--design "desc"` | Create a new voice from text description, save to voice store |
| `--clone file name` | Clone a voice from reference audio, save to voice store |
| `--model 0.6b\|1.7b` | Select model size (default: auto based on available RAM) |
| `--version` | Print version and exit |

### What's deliberately NOT in v1

| Deferred | Reason |
|----------|--------|
| `-r` rate / `--instruct` | Standard pacing for all output; tuning deferred to v2 |
| `-a` device selection | Default audio device only in v1 |
| `--interactive` | Word highlighting is complex; deferred |
| `--progress` | Nice-to-have; deferred |
| `--daemon` mode | Performance optimization; deferred to v2 |

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  diga (executable target)                            │
│                                                      │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ ArgumentParser│  │ AudioPlayback│  │ VoiceStore  │ │
│  │ (CLI parsing)│  │ (AVAudioEng) │  │ (JSON on    │ │
│  │              │  │              │  │  disk)       │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘ │
│         │                 │                 │        │
│  ┌──────▼─────────────────▼─────────────────▼──────┐ │
│  │            DigaEngine (orchestrator)             │ │
│  └──────────────────────┬──────────────────────────┘ │
└─────────────────────────┼────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ SwiftVoxAlta  │ │ mlx-audio-    │ │ AudioToolbox  │
│ (AudioConv,   │ │ swift (Qwen3  │ │ / AVFAudio    │
│  VoiceDesign) │ │ -TTS models)  │ │ (playback)    │
└───────────────┘ └───────────────┘ └───────────────┘
```

### Components

#### 1. `DigaCommand` (ArgumentParser)
- Swift ArgumentParser `@main` entry point
- Mirrors `say` semantics: bare args = text, `-f` = file, stdin fallback
- Validates voice names and output formats

#### 2. `DigaEngine` (Orchestrator)
- Loads model via `VoxAltaModelManager` (reuse existing actor)
- Routes to VoiceDesign or Base model depending on voice type
- Standard emotion/pacing params hardcoded — no user-facing knobs in v1
- Handles text chunking for long inputs (sentence-boundary splitting)

#### 3. `AudioPlayback`
- Uses `AVAudioEngine` + `AVAudioPlayerNode` for real-time playback
- Plays to default system output device
- Streams PCM buffers as synthesis produces them

#### 4. `VoiceStore`
- Persists designed/cloned voices as JSON + clone prompt data
- Default location: `~/.diga/voices/`
- Each voice: `{ name, type, designDescription?, clonePromptPath?, createdAt }`
- Built-in voice aliases map to VoiceDesign descriptions

#### 5. `AudioFileWriter`
- Wraps existing `AudioConversion` for WAV output
- Adds AIFF, M4A via `AVAudioFile` / `ExtendedAudioFile`

---

## Model Storage

Follows the intrusive-memory shared model convention established by SwiftBruja.

**LLM models** (SwiftBruja): `~/Library/Caches/intrusive-memory/Models/LLM/`
**TTS models** (diga/VoxAlta): `~/Library/Caches/intrusive-memory/Models/TTS/`

```
~/Library/Caches/intrusive-memory/Models/
├── LLM/                                          # SwiftBruja (existing)
│   └── mlx-community_Qwen2.5-7B-Instruct-4bit/
│       ├── config.json
│       ├── tokenizer.json
│       ├── tokenizer_config.json
│       └── model.safetensors
└── TTS/                                          # diga/VoxAlta (new)
    ├── mlx-community_Qwen3-TTS-12Hz-0.6B/
    │   ├── config.json
    │   ├── tokenizer.json
    │   └── model.safetensors
    └── mlx-community_Qwen3-TTS-12Hz-1.7B/
        ├── config.json
        ├── tokenizer.json
        └── model.safetensors
```

**Conventions** (matching BrujaModelManager):
- HuggingFace model IDs: `/` → `_` for directory names
- Model detected as available by presence of `config.json`
- Downloaded from HuggingFace Hub via `swift-transformers`
- Model auto-selected by available RAM (16GB+ → 1.7B, <16GB → 0.6B)
- Override with `--model 0.6b` or `--model 1.7b`

### First-Run Download

```
$ diga "Hello world"
Downloading Qwen3-TTS-12Hz-1.7B... (2.8 GB)
[████████████████████████████░░░░] 87%  1.2 GB/s  ETA 3s
Model ready.
Hello world  [audio plays]
```

---

## Voice Management

### Built-in Voices

Pre-baked VoiceDesign descriptions. Generated on first use, cached in voice store:

```
$ diga --voices
  Built-in:
    alex        Male, American, warm baritone, conversational
    samantha    Female, American, clear soprano, professional
    daniel      Male, British, deep tenor, authoritative
    karen       Female, Australian, alto, friendly

  Custom:
    (none — use --design or --clone to create)
```

### Custom Voices

```bash
# Design from text description
diga --design "Young female, Irish accent, bright and energetic" colleen

# Clone from reference audio
diga --clone ~/recording.wav myvoice

# Use them
diga -v colleen "Top of the morning"
diga -v myvoice "Hello from my cloned voice"
```

---

## Text Chunking

Qwen3-TTS has practical token limits. For long texts:

1. Split on sentence boundaries (NLTokenizer)
2. Group sentences into chunks of ~200 words
3. Synthesize chunks sequentially
4. For playback: stream each chunk as ready (overlap synthesis + playback)
5. For file output: concatenate all chunks, write once

---

## Build System

### Makefile

Following the SwiftProyecto/SwiftEchada pattern:

```makefile
SCHEME = diga
DESTINATION = platform=macOS,arch=arm64

.PHONY: resolve build install release test clean help

resolve:        ## Resolve SPM dependencies
	xcodebuild -resolvePackageDependencies -scheme $(SCHEME) -destination '$(DESTINATION)'

build:          ## Development build (swift build, no Metal shaders)
	swift build

install:        ## Debug build with xcodebuild + Metal shaders (DEFAULT)
	xcodebuild build -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)'
	@mkdir -p ./bin
	# copy binary + mlx-swift_Cmlx.bundle from DerivedData to ./bin/

release:        ## Release build with xcodebuild + Metal shaders
	xcodebuild build -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)'
	@mkdir -p ./bin
	# copy binary + mlx-swift_Cmlx.bundle from DerivedData to ./bin/

test:           ## Run unit tests
	xcodebuild test -scheme SwiftVoxAlta-Package -destination '$(DESTINATION)'

clean:          ## Clean all build artifacts
	rm -rf ./bin .build
	xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' || true

help:           ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := install
```

**Critical**: `diga` CLI MUST be built with `xcodebuild`, not `swift build`.
MLX requires Metal shaders (`mlx-swift_Cmlx.bundle`) colocated with the binary.

---

## CI/CD

### GitHub Actions: `tests.yml`

Following SwiftProyecto/SwiftEchada pattern — three jobs:

```yaml
name: Tests

on:
  pull_request:
    branches: [main]

concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true

jobs:
  code-quality:
    name: Code Quality
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Check for TODOs/FIXMEs
        run: # scan for new TODOs in diff
      - name: Check for print statements
        run: # scan Sources/ for print()

  unit-tests:
    name: macOS Unit Tests
    needs: code-quality
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild build -scheme SwiftVoxAlta-Package -destination 'platform=macOS'
      - name: Test
        run: xcodebuild test -scheme SwiftVoxAlta-Package -destination 'platform=macOS'
      - name: Upload test logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-output
          path: test_output_macos.txt
          retention-days: 7

  integration-tests:
    name: Integration Tests
    needs: code-quality
    runs-on: macos-26
    timeout-minutes: 15
    env:
      GIT_LFS_SKIP_SMUDGE: 1
    steps:
      - uses: actions/checkout@v4
      - name: Build release binary
        run: make release
      - name: Verify binary
        run: ./bin/diga --version
      - name: Verify Metal bundle
        run: test -d ./bin/mlx-swift_Cmlx.bundle
```

### GitHub Actions: `release.yml`

Following SwiftProyecto/SwiftEchada pattern — build, package, upload, dispatch:

```yaml
name: Release

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (e.g. v1.0.0)'
        required: true

concurrency:
  group: release-${{ github.ref }}

jobs:
  build-and-release:
    name: Build & Release
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Determine version
        id: version
        run: |
          TAG="${{ github.event.release.tag_name || github.event.inputs.tag }}"
          VERSION="${TAG#v}"
          echo "tag=$TAG" >> $GITHUB_OUTPUT
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Build release
        run: make release

      - name: Verify artifacts
        run: |
          test -f ./bin/diga
          test -d ./bin/mlx-swift_Cmlx.bundle

      - name: Package tarball
        run: |
          cd bin
          tar czf ../diga-${{ steps.version.outputs.version }}-arm64-macos.tar.gz \
            diga mlx-swift_Cmlx.bundle

      - name: Compute SHA256
        id: sha
        run: |
          SHA=$(shasum -a 256 diga-${{ steps.version.outputs.version }}-arm64-macos.tar.gz | awk '{print $1}')
          echo "sha256=$SHA" >> $GITHUB_OUTPUT

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: diga-${{ steps.version.outputs.version }}-arm64-macos.tar.gz

      - name: Trigger Homebrew tap update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.DEPLOY_TOKEN }}
          repository: intrusive-memory/homebrew-tap
          event-type: formula-update
          client-payload: |
            {
              "formula": "diga",
              "version": "${{ steps.version.outputs.tag }}",
              "repo": "intrusive-memory/SwiftVoxAlta"
            }
```

### Branch Protection

Required status checks on `main`:
```
- Code Quality
- macOS Unit Tests
- Integration Tests
```

---

## Homebrew Distribution

Pre-built binary via `intrusive-memory/homebrew-tap`:

```bash
brew tap intrusive-memory/tap
brew install diga
```

### Formula: `Formula/diga.rb`

```ruby
class Diga < Formula
  desc "On-device neural text-to-speech CLI powered by Qwen3-TTS"
  homepage "https://github.com/intrusive-memory/SwiftVoxAlta"
  url "https://github.com/intrusive-memory/SwiftVoxAlta/releases/download/v{VERSION}/diga-{VERSION}-arm64-macos.tar.gz"
  sha256 "{SHA256}"
  version "{VERSION}"

  depends_on arch: :arm64
  depends_on macos: :tahoe  # macOS 26+

  def install
    libexec.install "diga"
    libexec.install "mlx-swift_Cmlx.bundle"
    (bin/"diga").write_env_script libexec/"diga", {}
  end

  def caveats
    <<~EOS
      diga downloads the Qwen3-TTS model (~2.8 GB) on first run.
      Models are cached at ~/Library/Caches/intrusive-memory/Models/TTS/

      To use diga in place of the system say command:
        alias say=diga    # add to your .zshrc
    EOS
  end

  test do
    assert_match "diga", shell_output("#{bin}/diga --version")
  end
end
```

**Key details** (matching proyecto/echada pattern):
- Pre-built arm64 binary distribution (not source build)
- Binary + Metal bundle installed to `libexec` (colocated for shader access)
- Wrapper script in `bin` to exec the `libexec` binary
- Formula auto-updated by `repository_dispatch` from release workflow
- `DEPLOY_TOKEN` secret required with write access to homebrew-tap repo

---

## Package.swift Integration

New executable target alongside existing library:

```swift
.executableTarget(
    name: "diga",
    dependencies: [
        "SwiftVoxAlta",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    path: "Sources/diga"
),
```

New dependency:
```swift
.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
```

Library target stays clean — `diga` is a consumer, not a modification.

---

## Versioning

Unified with SwiftVoxAlta — single version source, single tag scheme:

```swift
// Sources/diga/Version.swift
static let version = "1.0.0"
```

Tags: `v1.0.0`, `v1.1.0`, etc. (same tags publish both library + CLI)

Release workflow: Follows SwiftProyecto/SwiftEchada SOP:
1. Work on `development` branch
2. PR `development` → `main`
3. CI passes, merge
4. `git tag -a v1.0.0 -m "Release v1.0.0"` on `main`
5. `gh release create v1.0.0 --title "v1.0.0" --notes "..."`
6. release.yml builds binary, uploads tarball, dispatches Homebrew update
7. Merge `main` back to `development`

---

## File Layout

```
Sources/diga/
  DigaCommand.swift       # @main ArgumentParser entry point
  DigaEngine.swift        # Orchestrator: model loading, synthesis, chunking
  AudioPlayback.swift     # AVAudioEngine real-time playback
  AudioFileWriter.swift   # WAV/AIFF/M4A file output
  VoiceStore.swift        # ~/.diga/voices/ persistence
  BuiltinVoices.swift     # Pre-baked voice descriptions
  Version.swift           # Version constant
```

---

## Fallback Behavior

If the model is not downloaded and download fails (no network, disk full):
- Fall back to Apple's `/usr/bin/say` with equivalent flags
- Print notice: `Using Apple TTS (run diga again with network access to download neural model)`

If the machine has insufficient RAM for even the 0.6B model:
- Fall back to Apple's `/usr/bin/say`
- Print notice explaining the memory requirement

---

## Dependencies

| Dependency | Purpose | Already in project? |
|-----------|---------|---------------------|
| SwiftVoxAlta | AudioConversion, VoiceDesigner, ModelManager | Yes (library target) |
| mlx-audio-swift | Qwen3-TTS inference | Yes (transitive) |
| swift-argument-parser | CLI flag parsing | **New** |
| AVFAudio / AudioToolbox | Playback + file I/O | System framework |
| Foundation (NLTokenizer) | Sentence splitting | System framework |

---

## Scope

v1 target: ~700 lines across 7 files. Gets you `diga "hello world"` through
the speaker, `diga -o out.wav "hello"` to file, `--design` / `--clone` for
voice creation, and `brew install diga` for distribution.
