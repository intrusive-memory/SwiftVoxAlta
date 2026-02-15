# GEMINI.md

**Gemini-specific instructions for SwiftVoxAlta**

For comprehensive project documentation, architecture, API reference, and development guidelines, see **[AGENTS.md](AGENTS.md)**.

---

## Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test`.

```bash
# ✅ CORRECT
make build
make test
xcodebuild build -scheme SwiftVoxAlta -destination 'platform=macOS'

# ❌ WRONG - Metal shaders won't compile
swift build
swift test
```

**Why**: Qwen3-TTS requires Metal shader compilation which only works with `xcodebuild`.

## Platform Constraints

- **ONLY** iOS 26.0+ and macOS 26.0+
- **NEVER** add `@available` attributes for older versions
- **Apple Silicon only** - M1/M2/M3/M4 required

## Git Workflow

- Branch: `development` → PR → `main`
- Never commit directly to `main`

---

**See [AGENTS.md](AGENTS.md) for:**
- Complete API documentation and usage examples
- Voice design pipeline and character analysis
- CLI commands and voice management
- Architecture patterns and design decisions
- Integration guides for SwiftHablare/Produciesta
