# REQUIREMENTS — Glosa Integration (SwiftVoxAlta)

**Status:** Draft / proposed
**Owner repo role:** TTS consumer — turns screenplay elements into audio via mlx-audio-swift.
**Primary deliverable:** Read the **audio coat** off SwiftCompartido's `GuionElementModel` and feed `spokenText` + `breathOffsets` + `instruct` into `Qwen3TTSModel.generate(...)`.

> One of four coordinated docs. See also:
> - `SwiftCompartido/REQUIREMENTS-glosa-integration.md` (produces the audio coat consumed here)
> - `mlx-audio-swift/REQUIREMENTS-glosa-integration.md` (the `breathOffsets` API)
> - `glosa-av/REQUIREMENTS-glosa-integration.md`

---

## 1. Context

This repo already calls the TTS engine — e.g. `DigaCLICore/DigaEngine.swift` (`qwenModel.generate(text:voice:...instruct:...)`) and `SwiftVoxAlta/VoxAltaVoiceProvider.swift`. Two blockers and one collision must be addressed to consume glosa breaths:

1. **mlx pin is too old.** `Package.swift` pins mlx-audio-swift to `0.8.6` (`upToNextMinor(from: "0.8.6")`). The `breathOffsets` parameter shipped in **0.9.0**. The pin must move to `0.9.x`.
2. **No glosa awareness yet.** This repo does not read any glosa data; it must consume SwiftCompartido's audio coat.
3. **Chunking collision.** `DigaEngine.chunkText(...)` already splits dialogue into duration-based chunks and loops `generate` per chunk. Glosa breath offsets are independent cut points measured against the *whole* line's spoken text. The two schemes must be reconciled (see FR3) or breaths will land at the wrong scalar positions inside arbitrary duration chunks.

---

## 2. Goal
When synthesizing a `GuionElementModel` (or its DTO) that carries glosa data, the audio is produced with breath seams at the authored offsets and the composed `instruct` applied — without VoxAlta knowing anything about glosa internals.

## 3. Functional requirements

### FR1 — Dependency bump
- Move the mlx-audio-swift pin from `0.8.6` to `0.9.x` (the line that introduced `generate(..., breathOffsets:)`). Re-resolve and re-test existing generation paths (the empty-`breathOffsets` path is byte-identical to the prior API, so non-glosa output must not change).
- Add SwiftCompartido as a dependency if not already present (VoxAlta consumes `GuionElementModel` / the audio-coat protocol from there). VoxAlta does **not** depend on glosa-av directly — it only sees the pure-value coat.

### FR2 — Consume the audio coat
- Read `spokenText`, `breathOffsets`, and `instruct` from SwiftCompartido's `SpeakableElement` representation.
- Pass them through: `qwenModel.generate(text: element.spokenText, voice:..., instruct: element.instruct, breathOffsets: element.breathOffsets, generationParameters:...)`.
- When `breathOffsets` is empty, behavior must equal the current no-breath path.

### FR3 — Reconcile with existing `chunkText`
Decide and implement the interaction between glosa breaths and `DigaEngine.chunkText()`:
- **Preferred:** when a line has glosa `breathOffsets`, treat glosa as the source of truth for that line — pass the whole `spokenText` to `generate(breathOffsets:)` and bypass `chunkText()` for it. (Glosa `BreathStrength` semantics already encode "chunk to fit budget" intent upstream.)
- **Fallback:** if duration limits must still cap chunk length, translate/clamp `breathOffsets` into each chunk's local unicode-scalar range and pass per-chunk offsets. More complex; only if FR3-preferred proves insufficient.
- Document the chosen behavior; add a test asserting offsets are not silently dropped or mis-mapped when both mechanisms are active.

### FR4 — Instruct handling
- Route glosa `instruct` into the existing `instruct:`/`GenerationContext` path. If both a glosa instruct and a parenthetical/voice-design instruct exist, define precedence (recommend: glosa instruct wins for the line; document it).

## 4. Non-functional requirements
- Non-glosa screenplays produce byte-identical audio to today (guard against regressions from the mlx bump and the new code path).
- No direct dependency on glosa-av (only SwiftCompartido + mlx-audio-swift).

## 5. Acceptance criteria
- AC1: A dialogue element with authored breaths synthesizes with seams at the expected offsets; total sample count equals the sum of per-segment counts (mirrors mlx's breath-generate contract).
- AC2: A dialogue element with no glosa data produces identical output to the pre-change code path.
- AC3: The mlx pin resolves to `0.9.x` and the existing VoxAlta test suite passes.
- AC4: `chunkText` reconciliation has a test proving breath offsets map to correct positions (or that whole-line glosa path is taken).

## 6. Risks & non-goals
- **RISK-1 (chunking):** the most error-prone area — duration chunking vs. glosa offsets. Get FR3 right with a dedicated test.
- **RISK-2 (pauses):** mlx has no silence/pause API; glosa `pausePoints` cannot be rendered today. Do not attempt to consume pauses until mlx exposes an API (see mlx doc). Surface this limitation rather than faking it.
- **RISK-3 (mlx 0.6.x note):** the current `0.8.6` pin carries a comment about a pinned mlx-swift transitive line; verify the `0.9.x` bump doesn't reintroduce the transitive conflict it was avoiding.
- **Non-goal:** parsing glosa markup (SwiftCompartido owns that).
- **Note — Produciesta:** `../Produciesta` is a parallel screenplay→audio consumer. If it also synthesizes from SwiftCompartido elements, it needs the same FR1–FR4 treatment; verify and, if so, add a sibling requirements doc there.
