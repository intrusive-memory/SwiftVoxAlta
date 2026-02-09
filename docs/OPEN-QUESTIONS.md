# Open Questions

Issues that need resolution before or during implementation.

## 1. mlx-audio-swift Maturity

**Question**: Is mlx-audio-swift production-ready for Qwen3-TTS inference, or do we need a fallback?

**Context**: mlx-audio-swift exists but its current state needs verification. If it's immature or incomplete, alternatives include:

- Wrapping `mlx-audio` (Python) via subprocess calls
- Using one of the Rust Qwen3-TTS implementations via C FFI
- Contributing directly to mlx-audio-swift to fill gaps

**Impact**: High. This is the core inference path. Everything else is plumbing around it.

**Action**: Spike on mlx-audio-swift to evaluate: Can it load Qwen3-TTS models? Does it support VoiceDesign mode? What's the API surface?

## 2. Fountain Parser: Build or Depend?

**Question**: Write our own Fountain parser or take a dependency?

**Considerations**:
- Fountain is a well-specified format, parsers aren't complex
- A Swift Fountain parser may already exist (needs research)
- If we build our own, it's a clean, testable module with no ML dependencies
- If we depend on an external one, we inherit its maintenance status

**Leaning**: Build our own. Fountain parsing is deterministic, well-scoped, and we need specific extraction patterns (character evidence gathering) that a generic parser might not optimize for.

## 3. SwiftBruja as Dependency vs. Shared Protocol

**Question**: Should SwiftVoxAlta depend on SwiftBruja directly, or should both conform to shared protocols from a common package?

**Options**:
- **Direct dependency**: SwiftVoxAlta imports SwiftBruja, calls `Bruja.query()`. Simple, works now.
- **Shared protocol package**: Extract common interfaces (model management, memory validation, cache paths) into a shared package. Both SwiftBruja and SwiftVoxAlta depend on it. Cleaner long-term but more upfront work.
- **Copy patterns, no dependency**: SwiftVoxAlta reimplements model management patterns independently. Duplicates code but zero coupling.

**Leaning**: Direct dependency for now. Extract shared protocols later if a third sibling emerges. Premature abstraction is worse than a little coupling.

## 4. Voice Clone Prompt Portability

**Question**: Are Qwen3-TTS voice clone prompts (speaker embeddings) portable across model versions?

**Context**: If Qwen releases an updated model, do locked voices need to be re-generated? If clone prompts are tied to a specific model checkpoint, we need to version-stamp voice locks and handle migration.

**Impact**: Medium. Affects long-term voice persistence strategy.

**Action**: Investigate what the clone prompt actually contains and whether it's model-version-dependent.

## 5. Multi-Language Scripts

**Question**: How do we handle scripts with dialogue in multiple languages?

**Context**: Qwen3-TTS supports 10 languages. A script might have characters who speak different languages, or a single character who switches languages mid-script.

**Considerations**:
- Language detection per line (or per character, with per-line override)
- Voice cloning works cross-language in Qwen3-TTS (clone a voice in English, render in Spanish)
- The Fountain format doesn't have a standard language annotation

**Leaning**: Default to auto-detection per line. Allow explicit language tags via a convention (e.g., `/* language: Spanish */` comment before a line).

## 6. Streaming vs. Batch Rendering

**Question**: Should the first version support streaming output, or batch-only?

**Context**: Qwen3-TTS supports streaming (~97ms latency to first packet). This enables real-time playback during rendering. But it adds complexity to the audio pipeline.

**Leaning**: Batch-only for v1. Streaming is a v2 feature. Get the pipeline correct before optimizing for latency.

## 7. Audio Post-Processing

**Question**: Should SwiftVoxAlta include any audio post-processing (normalization, noise floor, room tone)?

**Context**: Raw TTS output may have inconsistent levels between characters or lines. Professional audio workflows typically include normalization and room tone matching.

**Considerations**:
- Basic loudness normalization (LUFS targeting) is straightforward with AVFoundation
- Room tone / ambiance is out of scope (that's sound design, not voice synthesis)
- Per-character EQ or effects are out of scope

**Leaning**: Include basic loudness normalization. Nothing else. Users can post-process in their DAW.

## 8. Non-Fountain Input

**Question**: Should we support input formats beyond Fountain?

**Candidates**:
- Plain text with character attribution (`CHARACTER: Dialogue`)
- Final Draft XML (.fdx)
- Highland format
- Raw text (single narrator, no characters)

**Leaning**: Fountain first, as the primary format. Plain text with attribution as a simple fallback. Other formats as future extensions. The parser layer is modular enough to add formats without touching the rest of the pipeline.

## 9. Project Identity

**Question**: How are projects identified and tracked?

**Context**: Voice locks are per-project. We need a stable project identity that survives file moves and renames.

**Options**:
- Hash of the script file path (breaks on move)
- Hash of script content (breaks on any edit)
- User-assigned project name
- UUID generated on first parse, stored in a sidecar file

**Leaning**: UUID in a sidecar file (`.voxalta` file next to the script). Survives renames and edits. The sidecar maps the project UUID to its voice storage directory.
