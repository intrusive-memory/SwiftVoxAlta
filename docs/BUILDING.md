# Building & Testing

## Building from Source

**Important**: Use `xcodebuild` or the Makefile. Metal shaders required by Qwen3-TTS won't compile with `swift build`.

```bash
make build      # Development build
make release    # Release build + copy to ./bin
make install    # Debug build + copy to ./bin
```

## Testing

VoxAlta has two test suites: fast unit tests and slower integration tests.

### Test Targets

```bash
# Fast unit tests (library only, no binary required, ~5-10 seconds)
make test-unit

# Integration tests (builds diga binary, requires models/voices, ~15-60 seconds)
make test-integration

# Run both test suites sequentially
make test
```

**Unit tests** (`make test-unit`) validate the VoxAlta library code (voice design API, audio processing, character analysis) without requiring the `diga` binary. These are fast and suitable for rapid iteration during development.

**Integration tests** (`make test-integration`) spawn the `diga` binary as a subprocess and validate:
- Binary execution and command-line parsing
- Audio file generation (WAV, AIFF, M4A formats)
- File headers and format validation
- Audio quality (non-silence detection via RMS/peak analysis)

### Voice Cache Behavior

Integration tests use voice caching to avoid repeated generation costs:

**First run** (cold cache):
- Auto-downloads Qwen3-TTS models from HuggingFace (~3-4 GB one-time download)
- Auto-generates test voice "alex" (~60 seconds one-time cost)
- Caches voice at `~/Library/Caches/intrusive-memory/Voices/alex.voice`
- Total time: ~60-90 seconds

**Subsequent runs** (warm cache):
- Reuses cached voice from disk (instant load)
- Total time: ~15 seconds

Voice caches persist across test runs. Clear the cache to force regeneration:

```bash
rm -rf ~/Library/Caches/intrusive-memory/Voices/
```

### Local Development Workflow

**During active development:**
```bash
make test-unit  # Fast feedback loop (~5s)
```

**Before submitting a pull request:**
```bash
make test  # Runs both unit and integration tests
```

**First-time setup:**
```bash
make install  # Build diga binary
make test-integration  # Generate voice cache (one-time ~60s)
```

After the initial setup, integration tests will use the cached voice and complete in ~15 seconds.

### CI Behavior

GitHub Actions runs unit and integration tests in parallel jobs:

**Unit Tests Job:**
- Runs on `macos-26` runner
- No model download or voice generation required
- Completes in ~10 seconds

**Integration Tests Job:**
- Runs on `macos-26` runner
- Uses GitHub Actions cache for models and voices
- First CI run: Downloads models and generates voices (~90 seconds)
- Subsequent CI runs: Uses cached models/voices (~15 seconds)
- Uploads test audio artifacts on failure for debugging

Cache key: `tts-cache-v1` (shared across CI runs)
