# Diga CLI — Execution Plan

> **Status**: ON DECK — VoxAlta library sprints complete (222 tests, 6 sprints).
> Reference: [docs/CLI_SAY_CONCEPT.md](docs/CLI_SAY_CONCEPT.md)

---

## Overview

`diga` is a macOS CLI binary that replaces Apple's `/usr/bin/say` with on-device
Qwen3-TTS neural speech synthesis. It ships as an executable target inside the
SwiftVoxAlta package, distributed via `brew tap intrusive-memory/tap && brew install diga`.

### Assumptions

- VoxAlta library sprints (1–6) are complete ✅
- mlx-audio-swift fork is on `development` branch with VoiceDesign + Base model support ✅
- SwiftBruja shared model directory convention is established ✅
- `intrusive-memory/homebrew-tap` repo exists with `update-formula.yml` workflow

### Changes from original plan

1. **Tests folded into each sprint** — eliminated standalone test sprints I/J
2. **CI moved to Sprint 1** — validate from the first PR
3. **Sprints 2+3 parallelized** — model management and voice store are independent
4. **Sprints 5+6 parallelized** — playback and file output are independent
5. **8 sprints** (was 10), several parallelizable → faster wall-clock time

---

## Dependency Graph

```
Sprint 1 (Executable + Makefile + CI)
  ├──→ Sprint 2 (Model Management + Download) ──┐
  └──→ Sprint 3 (Voice Store + Built-in Voices) ─┤
                                                  ▼
                                     Sprint 4 (DigaEngine + Chunking)
                                       ├──→ Sprint 5 (Audio Playback) ──┐
                                       └──→ Sprint 6 (File Output) ─────┤
                                                                        ▼
                                                  Sprint 7 (CLI Integration + Fallback)
                                                              │
                                                              ▼
                                                  Sprint 8 (Release Workflow + Homebrew)
```

Parallelizable pairs: {2, 3} and {5, 6}

---

## Sprint 1: Executable Target + Makefile + CI

> **Priority**: P0 — Foundation. Everything depends on this.
> **Estimated tests**: 6+

### 1.1 — Add swift-argument-parser dependency to Package.swift
- Add `.package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")`
- Do NOT modify existing library target or its dependencies
- **Test**: `xcodebuild -resolvePackageDependencies -scheme SwiftVoxAlta-Package -destination 'platform=macOS'` succeeds

### 1.2 — Add diga executable target to Package.swift
- Add `.executableTarget(name: "diga", dependencies: ["SwiftVoxAlta", .product(name: "ArgumentParser", package: "swift-argument-parser")], path: "Sources/diga")`
- Add `"diga"` to products list as `.executable`
- **Test**: `xcodebuild build -scheme diga -destination 'platform=macOS,arch=arm64'` succeeds

### 1.3 — Create Version.swift
- Create `Sources/diga/Version.swift`
- Define `enum DigaVersion { static let current = "0.1.0" }`

### 1.4 — Create bare DigaCommand with --version
- Create `Sources/diga/DigaCommand.swift`
- `@main struct DigaCommand: ParsableCommand` with `--version` flag
- Print version and exit when `--version` is passed
- Print usage when no arguments given

### 1.5 — Create Makefile
- Create `Makefile` at project root following SwiftProyecto/SwiftEchada pattern
- Targets: `resolve`, `build`, `install` (default), `release`, `test`, `clean`, `help`
- `install` and `release` use `xcodebuild` with `-scheme diga`
- Copy binary + `mlx-swift_Cmlx.bundle` from DerivedData to `./bin/`
- `test` uses `xcodebuild test -scheme SwiftVoxAlta-Package`

### 1.6 — Update CI workflow
- Update `.github/workflows/tests.yml` to add integration job
- Integration Tests job: `make release` → `./bin/diga --version` → verify Metal bundle
- Ensure existing library tests still pass alongside new executable
- Update branch protection status checks via `gh api`

### 1.7 — Tests
- Version string is non-empty and matches expected format
- DigaCommand compiles and conforms to ParsableCommand
- `make release` produces `./bin/diga` and `./bin/mlx-swift_Cmlx.bundle`
- `./bin/diga --version` prints version string
- Existing 222 VoxAlta library tests still pass

### Exit Criteria
- Package.swift has executable target that builds
- `./bin/diga --version` prints version string
- `make release` produces binary + Metal bundle in `./bin/`
- CI runs on PR with library tests + integration smoke test
- Existing library target and tests unaffected

---

## Sprint 2: Model Management + Download

> **Priority**: P0 — Core infrastructure. Can run in **parallel with Sprint 3**.
> **Depends on**: Sprint 1
> **Estimated tests**: 10+

### 2.1 — Create DigaModelManager
- Create `Sources/diga/DigaModelManager.swift`
- Actor wrapping model download and availability checks for CLI use
- `modelsDirectory`: `~/Library/Caches/intrusive-memory/Models/TTS/` (matches SwiftBruja LLM convention)
- `modelDirectory(for modelId:)`: append model ID with `/` → `_` replacement
- `isModelAvailable(_:)`: check for `config.json` in model directory

### 2.2 — Implement RAM-based model selection
- Add `recommendedModel()` method to DigaModelManager
- Query system physical memory via `ProcessInfo.processInfo.physicalMemory`
- 16GB+ → `mlx-community/Qwen3-TTS-12Hz-1.7B` (better quality)
- <16GB → `mlx-community/Qwen3-TTS-12Hz-0.6B` (fits in memory)
- Support `--model` override via explicit model ID

### 2.3 — Implement model download with progress
- Add `downloadModel(_:progress:)` async method to DigaModelManager
- Download from HuggingFace Hub
- Required files: `config.json`, `tokenizer.json`, `tokenizer_config.json`, `model.safetensors`
- Print progress bar to stderr during download
- Skip download if model already exists (check `config.json`)
- Create directory structure if missing

### 2.4 — Wire model download into first-run flow
- On first invocation, check if recommended model is available
- If not, print download message and start download with progress
- After download completes, proceed with synthesis
- If `--model` flag specified, download that specific model

### 2.5 — Tests
- modelsDirectory points to correct path
- modelDirectory slugifies HuggingFace IDs (`/` → `_`)
- isModelAvailable returns false for missing model, true when config.json exists
- recommendedModel returns correct model for RAM thresholds
- Download to temp directory with mock/stub; verify directory created, skip-if-exists logic
- Command with missing model triggers download flow; existing model skips download
- **No tests require actual model downloads or network access**

### Exit Criteria
- TTS models stored at `~/Library/Caches/intrusive-memory/Models/TTS/`
- RAM-based model selection works
- First-run download with progress bar functions
- Model availability detection works correctly
- 10+ tests, all CI-safe

---

## Sprint 3: Voice Store + Built-in Voices

> **Priority**: P0 — Core infrastructure. Can run in **parallel with Sprint 2**.
> **Depends on**: Sprint 1
> **Estimated tests**: 14+

### 3.1 — Create VoiceStore
- Create `Sources/diga/VoiceStore.swift`
- Store location: `~/.diga/voices/`
- Index file: `~/.diga/voices/index.json`
- `StoredVoice` struct: `name`, `type` (enum: builtin/designed/cloned), `designDescription?`, `clonePromptPath?`, `createdAt`
- Methods: `listVoices()`, `getVoice(name:)`, `saveVoice(_:)`, `deleteVoice(name:)`
- Create directory if missing on first access

### 3.2 — Create BuiltinVoices
- Create `Sources/diga/BuiltinVoices.swift`
- Define `enum BuiltinVoices` with static voice descriptions:
  - `alex`: "Male, American, warm baritone, conversational"
  - `samantha`: "Female, American, clear soprano, professional"
  - `daniel`: "Male, British, deep tenor, authoritative"
  - `karen`: "Female, Australian, alto, friendly"
- Each returns a `StoredVoice` with `type: .builtin` and `designDescription` populated
- Methods: `all() -> [StoredVoice]`, `get(name:) -> StoredVoice?`

### 3.3 — Implement --voices flag
- Add `--voices` flag to DigaCommand
- When set, print formatted list of built-in + custom voices and exit
- Format: two sections "Built-in:" and "Custom:", each with `name    description` rows
- If no custom voices, print "(none — use --design or --clone to create)"

### 3.4 — Implement --design flag
- Add `--design` subcommand or flag to DigaCommand: `diga --design "description" name`
- Load VoiceDesign model via DigaModelManager
- Call VoiceDesigner from SwiftVoxAlta library to generate candidate audio
- Extract clone prompt from candidate, save to `~/.diga/voices/{name}.cloneprompt`
- Save voice entry to VoiceStore index
- Print confirmation: `Voice "name" created.`

### 3.5 — Implement --clone flag
- Add `--clone` subcommand or flag: `diga --clone reference.wav name`
- Validate reference audio file exists and is readable
- Load Base model via DigaModelManager
- Extract clone prompt from reference audio via VoiceLockManager
- Save clone prompt to `~/.diga/voices/{name}.cloneprompt`
- Save voice entry to VoiceStore with `type: .cloned`
- Print confirmation: `Voice "name" cloned from reference.wav`

### 3.6 — Tests
- VoiceStore: save/get/delete round-trip using temp directory
- VoiceStore: listVoices returns all saved, index.json round-trips, directory created on first access
- BuiltinVoices: `all()` returns 4 voices, each with non-empty name/description
- BuiltinVoices: `get(name:)` returns correct voice, nil for unknown
- `--voices` output contains "alex", "samantha", "daniel", "karen" and "Built-in:" header
- StoredVoice Codable round-trip
- **No tests require actual model downloads**

### Exit Criteria
- VoiceStore persists voices to `~/.diga/voices/` as JSON + clone prompt files
- 4 built-in voices defined with descriptions
- `--voices` lists all available voices
- `--design` creates new voices from text descriptions
- `--clone` creates new voices from reference audio
- 14+ tests, all CI-safe

---

## Sprint 4: DigaEngine + Text Chunking

> **Priority**: P1 — Synthesis orchestration. Core pipeline.
> **Depends on**: Sprint 2 AND Sprint 3
> **Estimated tests**: 12+

### 4.1 — Create DigaEngine orchestrator
- Create `Sources/diga/DigaEngine.swift`
- Actor that coordinates model loading, voice lookup, and synthesis
- Dependencies: `DigaModelManager`, `VoiceStore`, VoxAlta library types
- Method: `synthesize(text:voiceName:) async throws -> Data` (returns WAV PCM)
- Standard pacing/emotion params hardcoded internally — no external tuning

### 4.2 — Implement voice resolution in DigaEngine
- Given a voice name, resolve to clone prompt data:
  1. Check VoiceStore for custom voice → load clone prompt from disk
  2. Check BuiltinVoices → if first use, run VoiceDesign to generate and cache clone prompt
  3. If no voice name specified, use first built-in voice as default
- Throw clear error if voice not found

### 4.3 — Create TextChunker
- Create `Sources/diga/TextChunker.swift`
- Use `NLTokenizer` with `.sentence` unit to split text on sentence boundaries
- Group sentences into chunks of ~200 words maximum
- Return `[String]` array of chunks
- Handle edge cases: single word, empty string, very long sentence (don't split mid-sentence)

### 4.4 — Wire chunking into DigaEngine
- `synthesize(text:voiceName:)` chunks the text, synthesizes each chunk sequentially
- Concatenate WAV PCM data from all chunks (strip headers, append raw samples, write single header)
- Return single WAV Data covering full text

### 4.5 — Tests
- TextChunker: short text → 1 chunk; 500-word text → 2-3 chunks; empty → empty; single long sentence → 1 chunk
- TextChunker: chunk boundaries fall on sentence boundaries
- TextChunker: text with no sentence terminators handled gracefully
- DigaEngine: instantiates without error
- Voice resolution: resolve unknown name throws error; resolve built-in returns non-nil
- WAV concatenation: two WAV Data inputs → single valid WAV output

### Exit Criteria
- DigaEngine orchestrates model loading, voice resolution, and synthesis
- Text chunking splits on sentence boundaries at ~200 words
- Multi-chunk synthesis produces valid concatenated WAV output
- Built-in voices are lazily generated and cached on first use
- 12+ tests, all CI-safe

---

## Sprint 5: Audio Playback

> **Priority**: P1 — Primary output mode. Can run in **parallel with Sprint 6**.
> **Depends on**: Sprint 4
> **Estimated tests**: 6+

### 5.1 — Create AudioPlayback
- Create `Sources/diga/AudioPlayback.swift`
- Use `AVAudioEngine` + `AVAudioPlayerNode` for real-time playback
- Method: `play(wavData: Data) async throws` — plays WAV to default system output device
- Parse WAV header for sample rate, channels, bit depth
- Create `AVAudioPCMBuffer` from raw PCM samples
- Schedule buffer on player node, start engine, wait for completion

### 5.2 — Implement streaming playback for chunked audio
- Method: `playChunks(chunks: AsyncStream<Data>) async throws`
- As each chunk WAV arrives from DigaEngine, schedule its buffer immediately
- Overlap synthesis of chunk N+1 with playback of chunk N
- Wait for all buffers to finish playing before returning

### 5.3 — Wire playback into DigaCommand
- Default behavior (no `-o` flag): synthesize text → play through speaker
- `diga "hello world"` → DigaEngine.synthesize → AudioPlayback.play
- `diga -f input.txt` → read file → synthesize → play
- `diga` (no args, stdin is not TTY) → read stdin → synthesize → play

### 5.4 — Tests
- AudioPlayback initializes without error
- Can create PCM buffer from known WAV data
- Playing 2 sequential chunks completes without gaps or errors
- Command with bare text args triggers playback path
- Command with `-f` flag reads file

### Exit Criteria
- Audio plays through default system output device
- Chunked streaming playback works without gaps
- Bare text, -f file, and stdin input all route to playback
- 6+ tests

---

## Sprint 6: Audio File Output

> **Priority**: P1 — File output mode. Can run in **parallel with Sprint 5**.
> **Depends on**: Sprint 4
> **Estimated tests**: 8+

### 6.1 — Create AudioFileWriter
- Create `Sources/diga/AudioFileWriter.swift`
- Method: `write(wavData: Data, to path: String, format: AudioFormat) throws`
- `AudioFormat` enum: `.wav`, `.aiff`, `.m4a`
- WAV: write directly (data is already WAV PCM)
- AIFF: convert via `AVAudioFile` with `.aiff` settings
- M4A: convert via `AVAudioFile` with AAC `.m4a` settings

### 6.2 — Implement format inference from file extension
- Given output path, infer format: `.wav` → WAV, `.aiff`/`.aif` → AIFF, `.m4a` → M4A
- If `--file-format` flag is set, use that instead of inference
- If neither flag nor recognizable extension, default to WAV

### 6.3 — Wire file output into DigaCommand
- `-o file` flag: synthesize text → write to file (no playback)
- Print nothing on success (match `say -o` behavior)
- Print error to stderr on failure

### 6.4 — Tests
- Format inference: `.wav` → WAV; `.aiff` → AIFF; `.m4a` → M4A; `.bin` → WAV (default)
- `--file-format` flag overrides extension
- WAV write produces valid WAV file (verify RIFF header)
- AIFF write produces valid AIFF file (verify FORM header)
- M4A write produces non-empty file
- `-o` flag suppresses playback

### Exit Criteria
- File output works for WAV, AIFF, M4A formats
- Format inferred from extension or overridden by flag
- `-o` flag suppresses playback and writes file silently
- 8+ tests

---

## Sprint 7: CLI Integration + Fallback

> **Priority**: P2 — Polish and robustness.
> **Depends on**: Sprint 5 AND Sprint 6
> **Estimated tests**: 12+

### 7.1 — Implement -v voice flag
- `-v voice` selects voice by name from VoiceStore + BuiltinVoices
- `-v ?` lists available voices (same as `--voices`) and exits
- If voice not found, print error to stderr and exit with code 1
- Default voice when `-v` not specified: first built-in voice (alex)

### 7.2 — Implement -f file flag and stdin
- `-f path` reads text from file
- `-f -` reads text from stdin
- If no `-f` and no bare text args and stdin is not a TTY, read stdin
- If no input at all, print usage and exit

### 7.3 — Implement --model flag
- `--model 0.6b` forces 0.6B model
- `--model 1.7b` forces 1.7B model
- Overrides RAM-based auto-selection
- Invalid model value prints error and exits

### 7.4 — Implement Apple TTS fallback
- If model not available and download fails (no network, disk full): fall back to `/usr/bin/say`
- Map diga flags to say flags: `-v` → `-v`, `-o` → `-o`, `-f` → `-f`, text args pass through
- Print notice to stderr: `"Using Apple TTS (run diga again with network to download neural model)"`
- If machine has insufficient RAM for 0.6B model: fall back to say with notice

### 7.5 — Wire all flags into unified DigaCommand
- Ensure all flags compose correctly: `-v alex -o out.wav -f input.txt`
- Mutual exclusion: `-o` (file) and playback are exclusive
- `--voices`, `--design`, `--clone`, `--version` are standalone commands (exit after)
- Regular synthesis: resolve voice → load model → chunk text → synthesize → play or write

### 7.6 — Tests
- `-v alex` uses alex voice; `-v ?` prints voice list; `-v nonexistent` exits with error
- `-f /tmp/input.txt` reads file; `echo "hello" | diga` reads stdin; no input prints usage
- `--model 0.6b` selects 0.6B; `--model invalid` exits with error
- Fallback flag mapping: diga flags → say flags
- Fallback triggers when model unavailable; notice printed to stderr
- Combined flags work: `-v daniel -o /tmp/out.wav "test"` produces file

### Exit Criteria
- All CLI flags work individually and in combination
- Voice selection, file input, stdin, model override all functional
- Fallback to Apple TTS works when model unavailable
- Error messages print to stderr, audio to stdout/speaker
- 12+ tests

---

## Sprint 8: Release Workflow + Homebrew

> **Priority**: P2 — Shipping. Final sprint.
> **Depends on**: Sprint 7
> **Estimated tests**: 4+ (mostly CI validation)

### 8.1 — Create release.yml workflow
- Create `.github/workflows/release.yml`
- Trigger: `release` published event + manual `workflow_dispatch` with tag input
- Build: `make release`
- Package: `diga-{VERSION}-arm64-macos.tar.gz` containing binary + Metal bundle
- Compute SHA256
- Upload tarball to GitHub Release via `softprops/action-gh-release@v2`
- Dispatch Homebrew tap update via `peter-evans/repository-dispatch@v3` to `intrusive-memory/homebrew-tap`

### 8.2 — Create Homebrew formula
- Create `Formula/diga.rb` in `intrusive-memory/homebrew-tap` repo
- Pre-built binary distribution: `depends_on arch: :arm64`, `depends_on macos: :tahoe`
- Install binary + Metal bundle to `libexec`, wrapper script in `bin`
- Caveats: model download notice, alias suggestion
- Formula test: `assert_match "diga", shell_output("#{bin}/diga --version")`

### 8.3 — Update branch protection
- Update required status checks on `main` to include:
  - Code Quality
  - macOS Unit Tests
  - Integration Tests
- Use `gh api` to update protection rules

### 8.4 — Binary smoke tests
- `./bin/diga --version` → verify output contains version string
- `./bin/diga --help` → verify output contains usage info
- `./bin/diga --voices` → verify output contains "alex", "Built-in:"
- Manual workflow_dispatch with test tag builds and packages correctly

### Exit Criteria
- Release workflow builds, packages, uploads, and dispatches Homebrew update
- Homebrew formula installs working binary
- Branch protection enforces CI passage
- `brew install diga` → `diga --version` works

---

## Sprint Summary

| Sprint | Name | Priority | Depends On | Parallel With | Est. Tests |
|--------|------|----------|------------|---------------|------------|
| 1 | Executable + Makefile + CI | P0 | — | — | 6+ |
| 2 | Model Management + Download | P0 | 1 | **3** | 10+ |
| 3 | Voice Store + Built-in Voices | P0 | 1 | **2** | 14+ |
| 4 | DigaEngine + Text Chunking | P1 | 2, 3 | — | 12+ |
| 5 | Audio Playback | P1 | 4 | **6** | 6+ |
| 6 | Audio File Output | P1 | 4 | **5** | 8+ |
| 7 | CLI Integration + Fallback | P2 | 5, 6 | — | 12+ |
| 8 | Release Workflow + Homebrew | P2 | 7 | — | 4+ |

**Total estimated tests**: 72+
**Critical path**: 1 → 2 → 4 → 5 → 7 → 8 (6 sprints sequential)
**Wall-clock sprints** (with parallelization): 6

---

## Resolved Decisions

1. **No alias install**: Homebrew caveats suggest `alias say=diga` but no `--install-alias`
   command. Users manage their own shell configuration.

2. **Model storage**: `~/Library/Caches/intrusive-memory/Models/TTS/` — parallel to
   SwiftBruja's `~/Library/Caches/intrusive-memory/Models/LLM/`. Same slug convention
   (HuggingFace ID with `/` → `_`), same `config.json` detection.

3. **Standard pacing**: v1 hardcodes emotion/pacing params in DigaEngine. No `--instruct`,
   no `-r rate`. Deferred to v2.

4. **Homebrew distribution**: Pre-built arm64 binary via `intrusive-memory/homebrew-tap`.
   Formula auto-updated by `repository_dispatch` from release.yml. Matches
   SwiftProyecto/SwiftEchada pattern exactly.

5. **Versioning**: Unified with SwiftVoxAlta. Single tag scheme (`v1.0.0`). Version
   constant in `Sources/diga/Version.swift`.

6. **CI/CD**: Tests run from Sprint 1 onwards. Release workflow added in Sprint 8.

7. **Fallback**: When model unavailable, delegate to `/usr/bin/say` with mapped flags
   and print notice to stderr.

8. **Tests per sprint**: Each sprint includes its own tests (learned from VoxAlta execution).
   No standalone test sprints.
