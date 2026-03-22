# Phonetic Dictionary

## Summary

A per-project pronunciation override system. Authors define a key/value map in their `PROJECT.md` frontmatter where keys are correctly-spelled words and values are phonetic respellings. VoxAlta substitutes these before passing text to Qwen3-TTS, improving pronunciation of names, jargon, and ambiguous words with zero LLM overhead.

## Motivation

Qwen3-TTS has solid built-in grapheme-to-phoneme, but it can't know how to pronounce made-up character names, technical terms, or regional words. Rather than running an expensive LLM preprocessing pass on every chunk, a static dictionary gives authors explicit control over pronunciation at no runtime cost.

## PROJECT.md Frontmatter Schema

New top-level key `phonetic_dictionary` — a YAML mapping of `word → phonetic spelling`:

```yaml
---
type: project
title: "My Podcast"
author: "Tom Stovall"
created: 2026-03-04T00:00:00Z

tts:
  model: "1.7b"

phonetic_dictionary:
  Cthulhu: "kuh-THOO-loo"
  kubectl: "cube-control"
  Hermione: "her-MY-oh-nee"
  Nguyen: "win"
  GIF: "jiff"
  Euler: "OY-ler"
  Tao: "dow"
  Lao Tzu: "low dzuh"
  Sigur Ros: "SEE-gur rohs"

cast:
  - character: NARRATOR
    voiceDescription: "Warm baritone"
---
```

## Requirements

### R1: Schema

- **R1.1**: `phonetic_dictionary` is an optional top-level key in PROJECT.md frontmatter.
- **R1.2**: Type is `[String: String]` — keys are case-sensitive original words, values are phonetic respellings.
- **R1.3**: Keys may be multi-word (e.g., `"Lao Tzu": "low dzuh"`).
- **R1.4**: An empty or missing `phonetic_dictionary` is valid and means no substitutions.

### R2: Parsing

- **R2.1**: SwiftProyecto (or whichever crate owns PROJECT.md parsing) deserializes `phonetic_dictionary` into a `[String: String]` dictionary.
- **R2.2**: Parsing failure of `phonetic_dictionary` should warn but not block project loading — fall back to empty dictionary.

### R3: Substitution

- **R3.1**: VoxAlta applies phonetic substitution **after** text chunking but **before** passing text to Qwen3-TTS.
- **R3.2**: Substitution is **whole-word, case-insensitive match** — `"Tao"` matches `"tao"`, `"Tao"`, `"TAO"` but not `"Taoist"`.
- **R3.3**: Multi-word keys match as contiguous sequences — `"Lao Tzu"` matches the two-word phrase, not individual words.
- **R3.4**: Longer keys take precedence over shorter keys (greedy match). If the dictionary has both `"New York"` and `"New York City"`, the three-word match wins.
- **R3.5**: Original text is **never modified** — substitution produces a transient copy used only for TTS input.

### R4: Integration Points

- **R4.1**: `DigaEngine.synthesize()` accepts an optional `phoneticDictionary: [String: String]` parameter.
- **R4.2**: Produciesta passes the parsed dictionary from PROJECT.md through to VoxAlta at synthesis time.
- **R4.3**: The `diga` CLI `speak` and `synthesize` commands accept an optional `--project` flag that loads the dictionary from a PROJECT.md file.
- **R4.4**: The `diga` CLI also accepts `--phonetic KEY=VALUE` flags for ad-hoc overrides (additive with project dictionary, CLI wins on conflict).

### R5: Validation

- **R5.1**: `echada validate` (or equivalent) warns on dictionary entries where the key and value are identical (no-op entries).
- **R5.2**: Warn on suspiciously long values (>50 chars) — likely not a phonetic respelling.

### R6: Testing

- **R6.1**: Unit tests for substitution logic — single word, multi-word, case insensitivity, greedy matching, no partial matches.
- **R6.2**: Unit test confirming empty/missing dictionary is a no-op.
- **R6.3**: Integration test loading a PROJECT.md with `phonetic_dictionary` and verifying the substituted text reaches the TTS engine.

## Out of Scope

- **IPA notation** — Qwen3-TTS doesn't consume IPA, so plain phonetic respelling is the right format.
- **Per-character dictionaries** — one dictionary per project is sufficient. If a character pronounces a word differently, that's a voice-acting nuance TTS can't capture anyway.
- **LLM-assisted dictionary generation** — possible future enhancement where an LLM suggests entries, but not part of this feature.
- **SSML** — Qwen3-TTS doesn't support SSML markup.

## Open Questions

1. Should `phonetic_dictionary` also be loadable from a standalone YAML file (e.g., `phonetic.yml`) for sharing across projects?
2. Should Produciesta's web UI surface dictionary entries for editing, or is PROJECT.md-only sufficient?
