# FIXME: Auto-Sentence Chunking for Long ICL Generations

> **Status (2026-05-09)**: ✅ **Implemented and shipped.** All 21 unit tests pass under `make test-unit` (`Tests/SwiftVoxAltaTests/VoiceLockManagerChunkingTests.swift`). This document is preserved as historical record of the spec, design decisions, and rationale; the working API is documented in `AGENTS.md` under `GenerationSettings`.
>
> **Cross-references**:
> - **Architecture rationale**: [`SENTENCE_CHUNKING_DISCUSSION.md`](SENTENCE_CHUNKING_DISCUSSION.md) — why chunking lives in VoxAlta, design trade-offs, decision log.
> - **Cross-package contract (GLOSA)**: [`../../../glosa-av/REQUIREMENTS.md` §4.8](../../../glosa-av/REQUIREMENTS.md) — note for GLOSA about how chunking interacts with the per-line instruct contract; documents the future option of sub-line gradient instructs.
> - **Drift root-cause analysis**: `/Users/stovak/Projects/podcast-tao-de-jing/episodes/chapter_2-findings.md`.
> - **Adaptive sampling fixes (already shipped)**: `mlx-audio-swift` commit `ea8548d`.

## Problem

**Reference-anchor dilution** is the dominant cause of prosody drift in long ICL generations.

When generating long audio segments (~23-30s), the reference audio codes (69 codes, ~2.96s) become a tiny fraction of the total context:
- Short utterance (Title, 37 codes): ratio 0.67 → strong prosody anchor
- Long exposition (element 11, 289 codes): ratio 0.19 → weak prosody anchor

The "TRIM ratio" (`refCodes / fullCodes`) drops from ~0.67 to ~0.19 for long segments. Prosody, cadence, and microintonation are anchored **only** by the in-context reference code stream (not by the speaker embedding), and that anchor weakens monotonically as `fullCodes` grows. Once the model attends mostly to its own recent output, prosody drifts away from the reference pattern.

**Evidence**: Chapter 2 element 11 drifts at 1:30. TRIM ratio = 0.193 (69 ref codes / 358 total codes).

## Solution

**Auto-chunk long utterances at sentence boundaries** before ICL generation, keeping the TRIM ratio above ~0.30.

### Strategy

1. **Detect long utterances**: Before calling `generateWithClonePrompt()`, estimate duration from text length
2. **Split at sentence boundaries**: If estimated duration > threshold (e.g., 12s), split text at `.`, `?`, `!`
3. **Generate each chunk** with the same reference codes (maintains consistent prosody anchor)
4. **Concatenate with natural pause** (e.g., 250ms silence between chunks)

**Benefits**:
- Keeps TRIM ratio above ~0.30 consistently (strong prosody anchor throughout)
- No script changes needed (transparent to the user)
- Natural pause between sentences improves clarity
- Proven technique (mirrors professional narration patterns)

### Target Threshold

**Recommended**: 10-12s per chunk (TRIM ratio ~0.25-0.30)

**Why**:
- 12s ≈ 288 codes at 24Hz
- 69 ref codes / (69 + 288) = 0.193 (too low)
- Target: 69 ref codes / (69 + 200) = 0.257 (acceptable)
- Sweet spot: ~8-10s per chunk → TRIM ratio ~0.3

## Implementation

### Where to Implement

**Two options**:

1. **SwiftVoxAlta** (Recommended): Add chunking logic in `VoiceLockManager.generateAudio()` before calling the mlx-audio-swift API
2. **mlx-audio-swift**: Add chunking logic inside `generateWithClonePrompt()` itself

**Recommendation**: Implement in **SwiftVoxAlta** because:
- Keeps mlx-audio-swift focused on low-level generation
- SwiftVoxAlta is the orchestration layer (right abstraction level)
- Easier to A/B test and disable if needed
- Can log chunking decisions in VoxAlta telemetry

### High-Level Algorithm

```swift
func generateAudio(
    text: String,
    voiceLock: VoiceLock,
    ...
    settings: GenerationSettings
) async throws -> Data {
    // 1. Estimate duration
    let estimatedDuration = estimateDuration(text: text, settings: settings)
    
    // 2. If duration > threshold, split at sentences
    let chunks: [String]
    if estimatedDuration > 12.0 {
        chunks = splitAtSentences(text: text, maxDuration: 10.0)
        VoiceLockManagerLogger.log("Auto-chunking long text into \(chunks.count) sentences")
    } else {
        chunks = [text]
    }
    
    // 3. Generate each chunk
    var audioChunks: [Data] = []
    for (i, chunk) in chunks.enumerated() {
        let audio = try await generateSingleChunk(chunk, voiceLock, ...)
        audioChunks.append(audio)
        
        // 4. Add natural pause between chunks (except after last)
        if i < chunks.count - 1 {
            audioChunks.append(generateSilence(duration: 0.25))  // 250ms pause
        }
    }
    
    // 5. Concatenate all chunks
    return concatenateAudio(audioChunks)
}
```

### Required Helper Functions

#### 1. `estimateDuration(text:settings:)`

Estimate audio duration from text length:

```swift
private static func estimateDuration(text: String, settings: GenerationSettings) -> TimeInterval {
    // Rough heuristic: 1 character ≈ 0.055 seconds of audio (based on empirical data)
    // Adjust based on observed targetTokens/duration ratio from telemetry
    let estimatedSeconds = Double(text.count) * 0.055
    return estimatedSeconds
}
```

**Calibration**: Use Chapter 2 telemetry to tune the constant:
- Element 11: 421 chars → 23.12s → 0.055 s/char ✓
- Element 12: 502 chars → 27.12s → 0.054 s/char ✓

#### 2. `splitAtSentences(text:maxDuration:)`

Split text at sentence boundaries using Foundation's ICU-backed segmenter, then pack into duration-bounded chunks:

```swift
private static func splitAtSentences(text: String, maxDuration: TimeInterval) -> [String] {
    // 1. ICU-backed sentence segmentation -- handles abbreviations (Dr., Mr.),
    //    decimals (3.14), and ellipses correctly. Zero dependencies.
    var sentences: [String] = []
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                             options: .bySentences) { substring, _, _, _ in
        if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            sentences.append(s)
        }
    }

    // 2. Pack sentences into duration-bounded chunks.
    var chunks: [String] = []
    var currentChunk = ""

    for sentence in sentences {
        let candidate = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence
        if estimateDuration(text: candidate, settings: .default) > maxDuration && !currentChunk.isEmpty {
            chunks.append(currentChunk)
            currentChunk = sentence
        } else {
            currentChunk = candidate
        }
    }

    if !currentChunk.isEmpty {
        chunks.append(currentChunk)
    }

    return chunks.isEmpty ? [text] : chunks
}
```

**Why Foundation, not regex**: ICU's `BreakIterator` handles abbreviations, decimals, and ellipses correctly with zero new dependencies. See `SENTENCE_CHUNKING_DISCUSSION.md` §1 for the rejected regex alternative and the upgrade path to `NaturalLanguage.NLTokenizer` if token-level analysis is ever needed.

**Edge case — single sentence longer than `maxDuration`**: this implementation emits the over-long sentence as its own chunk (better than mid-sentence cut). The shipped adaptive sampling fixes (`mlx-audio-swift` commit `ea8548d`) reduce drift severity for these outliers. If drift still occurs on individual long sentences, fall back to clause-level splitting at `,` and `;` *within* the offending sentence — defer until empirically observed.

#### 3. `generateSilence(duration:)`

Generate silent audio:

```swift
private static func generateSilence(duration: TimeInterval) -> Data {
    let sampleRate = 24000  // Match Qwen3-TTS output
    let numSamples = Int(duration * Double(sampleRate))
    let silentSamples = [Int16](repeating: 0, count: numSamples)
    
    // Convert to WAV format (same as mlx-audio-swift output)
    return AudioConversion.samplesToWAVData(silentSamples, sampleRate: sampleRate)
}
```

**Status**: `AudioConversion.buildWAVData(pcmSamples:sampleRate:)` already exists (`Sources/SwiftVoxAlta/AudioConversion.swift:132`). Silence is just `[Int16](repeating: 0, count: numSamples)` fed into it — no new helper needed, just a thin wrapper in `VoiceLockManager` for ergonomics.

#### 4. `concatenateAudio([Data])`

Concatenate multiple WAV files:

```swift
private static func concatenateAudio(_ chunks: [Data]) throws -> Data {
    // Parse WAV headers, extract raw PCM data, concatenate, re-wrap in WAV
    // SwiftFFMpeg or CoreAudio can do this
    
    // Simplified: assume all chunks have same format (24kHz, mono, 16-bit PCM)
    var combinedPCM = Data()
    for chunk in chunks {
        let pcm = try AudioConversion.extractPCM(from: chunk)
        combinedPCM.append(pcm)
    }
    
    return try AudioConversion.wrapPCMInWAV(combinedPCM, sampleRate: 24000)
}
```

**Status**: `AudioConversion` already has the building blocks — `parseFmtAndDataChunks` (private WAV header parser at line 178) and `buildWAVData` (line 132). Implementation needs:
1. Promote/wrap `parseFmtAndDataChunks` so a public `pcmData(from: Data) throws -> Data` slices out the PCM payload.
2. Add public `concatenateWAVs(_ chunks: [Data]) throws -> Data` — extract PCM from each, concatenate, re-wrap with `buildWAVData`.

Assumes uniform format (24 kHz mono 16-bit PCM — Qwen3-TTS output is consistent). No SwiftFFMpeg or AVFoundation dependency required.

### Files to Modify

### Code

1. **`SwiftVoxAlta/Sources/SwiftVoxAlta/GenerationSettings.swift`**:
   - Add `enableAutoChunking: Bool` (default `true`)
   - Add `chunkTargetDuration: TimeInterval` (default `10.0`)
   - Add `chunkPauseDuration: TimeInterval` (default `0.25`)
   - Optional: `estimatedSecondsPerChar: Double` (default `0.055`) — only if per-call tuning is needed; otherwise hardcoded constant in `VoiceLockManager`

2. **`SwiftVoxAlta/Sources/SwiftVoxAlta/VoiceLockManager.swift`**:
   - Add `estimateDuration(text:settings:) -> TimeInterval`
   - Add `splitAtSentences(text:maxDuration:) -> [String]` (Foundation `enumerateSubstrings(.bySentences)`-based)
   - Add `generateSilence(duration:sampleRate:) -> Data` (thin wrapper around `AudioConversion.buildWAVData`)
   - Modify `generateAudio(text:voiceLock:...)` to chunk before generating, accumulate chunks + silence, concatenate via `AudioConversion.concatenateWAVs`
   - Add chunking telemetry: chunk count, per-chunk char/duration, per-chunk TRIM ratio

3. **`SwiftVoxAlta/Sources/SwiftVoxAlta/AudioConversion.swift`**:
   - Promote/wrap `parseFmtAndDataChunks` to expose a public `pcmData(from: Data) throws -> Data`
   - Add public `concatenateWAVs(_ chunks: [Data]) throws -> Data` (PCM extract + concatenate + re-wrap)
   - `buildWAVData` already present — no change

### Tests

4. **`SwiftVoxAlta/Tests/SwiftVoxAltaTests/VoiceLockManagerChunkingTests.swift`** (new file):
   - Short text passthrough (estimated duration < threshold → single chunk, identity)
   - Long prose chunked at sentence boundaries (verify chunk count and per-chunk duration)
   - Abbreviation handling: `Dr.`, `Mr.`, `e.g.`, `i.e.` do not produce false sentence breaks
   - Decimal handling: `3.14`, `1.5x`, `v2.0` do not produce false breaks
   - Silence inserted between chunks (verify `chunkPauseDuration` via PCM byte count)
   - WAV concat round-trip: decode each chunk, concatenate manually, byte-compare against `concatenateWAVs` output
   - `enableAutoChunking = false` disables the path entirely (single-pass behavior preserved)
   - Single sentence longer than `maxDuration` → emits as its own oversized chunk (no mid-sentence cut)

### Documentation

5. **`SwiftVoxAlta/AGENTS.md`**:
   - Document new `GenerationSettings` fields
   - Note that chunking is transparent and on-by-default
   - Cross-link to `FIXME-sentence-chunking.md` (spec) and `SENTENCE_CHUNKING_DISCUSSION.md` (rationale)

### Already-handled / no-change

- **`mlx-audio-swift`** — chunking lives one layer up; adaptive sampling fixes already shipped (`ea8548d`).
- **`Produciesta`** — transparent. Callers can override `chunkTargetDuration` if they want shorter/longer chunks per-podcast, but require no code changes.
- **`glosa-av`** — already documented in `glosa-av/REQUIREMENTS.md` §4.8 (cross-package contract note about how chunking interacts with the per-line instruct contract).

## Testing

### 1. Re-render Chapter 2 with chunking enabled

```bash
cd /Users/stovak/Projects/podcast-tao-de-jing
bin/produciesta generate episodes/chapter-02.fountain \
    --output episodes/audio/chapter-02-chunked.m4a \
    --verbose > episodes/chapter-02-chunked.log 2>&1
```

### 2. Check telemetry logs

```bash
grep "Auto-chunking" episodes/chapter-02-chunked.log
```

Expected output for element 11 (421 chars, estimated ~23s):

```
[VoiceLockManager] Auto-chunking long text into 3 sentences
[VoiceLockManager] Chunk 1/3: "Chapter Two reveals that all opposites are interdependent—they define and create each other." (91 chars, ~5.0s)
[VoiceLockManager] Chunk 2/3: "Beauty exists because of ugliness; good exists because of evil." (65 chars, ~3.6s)
[VoiceLockManager] Chunk 3/3: "Difficulty and ease, long and short, high and low, before and after—these pairs arise together and give meaning to one another." (127 chars, ~7.0s)
```

### 3. Verify TRIM ratios

```bash
grep "TRIM ratio" episodes/chapter-02-chunked.log
```

Expected: All chunks should have TRIM ratio > 0.25 (vs 0.193 for the unchunked version).

### 4. Compare drift

Listen to:
- `episodes/audio/chapter-02.m4a` (original, drifts at 1:30)
- `episodes/audio/chapter-02-chunked.m4a` (chunked, should not drift)

Expected: No drift, natural pause between sentences.

## Success Criteria

- [ ] Long text (>12s) automatically split at sentence boundaries
- [ ] Each chunk has TRIM ratio > 0.25
- [ ] Natural 250ms pause between chunks
- [ ] No prosody drift in long expositions
- [ ] Short utterances (<12s) pass through unchanged (no unnecessary chunking)
- [ ] Telemetry logs chunk count and durations

## Tuning Parameters

### `maxDuration` (Default: 10.0s)

Controls when to flush current chunk:

- **8s**: More aggressive chunking, higher TRIM ratio (~0.35), more pauses
- **10s**: Recommended, balanced
- **12s**: Less aggressive, lower TRIM ratio (~0.25), fewer pauses

### `pauseDuration` (Default: 0.25s)

Natural pause between chunks:

- **0.15s**: Minimal pause, may sound rushed
- **0.25s**: Recommended, natural breath pause
- **0.35s**: Longer pause, more deliberate delivery

## Notes

- **This is the primary fix** for audio drift (addresses the dominant root cause)
- Adaptive repPenalty and temperature scaling are complementary
- All three fixes together should eliminate drift comprehensively
- This implementation is transparent to the user (no script changes required)
- Can be disabled via a flag in `GenerationSettings` if needed (e.g., `enableAutoChunking: Bool`)

## Status

- ✅ Adaptive repetition penalty + temperature scaling shipped in `mlx-audio-swift` (commit `ea8548d`).
- ✅ Sentence-detection strategy decided: Foundation `enumerateSubstrings(.bySentences)` (see `SENTENCE_CHUNKING_DISCUSSION.md` §1).
- ✅ Audio concatenation strategy decided: pure-Swift WAV concat using existing `AudioConversion` helpers (see §3 of discussion doc).
- ✅ GLOSA cross-package contract documented (`glosa-av/REQUIREMENTS.md` §4.8).
- ⏸️ Implementation: ready to start. Track progress via the [Success Criteria](#success-criteria) checklist above and the [Files to Modify](#files-to-modify) checklist.
