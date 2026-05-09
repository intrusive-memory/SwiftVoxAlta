# Sentence Chunking for Long TTS Generations — Architecture Discussion

**Date**: 2026-05-09  
**Context**: Addressing audio drift in long ICL voice cloning generations (20-30s)  
**Related**: See `FIXME-sentence-chunking.md` for full implementation specification

---

## Background

Audio drift analysis from `podcast-tao-de-jing/episodes/chapter_2-findings.md` identified **reference-anchor dilution** as the dominant cause of prosody drift in long generations:

- Short utterance (Title, 37 codes): TRIM ratio 0.67 → strong prosody anchor
- Long exposition (element 11, 289 codes): TRIM ratio 0.19 → weak prosody anchor

As `fullCodes` grows, the reference audio codes (69 codes, ~2.96s) become a tiny fraction of the total context. Prosody, cadence, and microintonation are anchored **only** by the in-context reference code stream (not by the speaker embedding), and that anchor weakens monotonically. Once the model attends mostly to its own recent output, prosody drifts away from the reference pattern.

**Solution**: Auto-chunk long utterances at sentence boundaries before ICL generation, keeping the TRIM ratio above ~0.30.

---

## Completed Work (2026-05-09)

### 1. Adaptive Repetition Penalty (mlx-audio-swift)
- ✅ Implemented exponential decay: `1.0 + (basePenalty - 1.0) * exp(-codes / 200)`
- ✅ Prevents pathological suppression of sustained vowels
- ✅ Committed and pushed to `mlx-audio-swift/development` (commit ea8548d)

### 2. Adaptive Temperature Scaling (mlx-audio-swift)
- ✅ Implemented length-based scaling: `temp * (1.0 - 0.3 * min(1.0, estimatedCodes / 400))`
- ✅ Reduces sampling variance in long utterances
- ✅ Committed and pushed to `mlx-audio-swift/development` (commit ea8548d)

### 3. Patch Release
- 🔄 Agent running `/ship-swift-library` to create patch release with drift fixes

---

## Architecture Decision: Where Should Chunking Live?

### Current Stack

```
Produciesta (podcast CLI/app)
    ↓ calls
SwiftVoxAlta (TTS orchestration)
    ↓ VoiceLockManager.generateAudio()
    ↓ calls
mlx-audio-swift (low-level TTS inference)
    ↓ Qwen3TTSModel.generateWithClonePrompt()
```

### Option 1: **SwiftVoxAlta** (Recommended ✅)

**Placement**: `VoiceLockManager.generateAudio()` — before calling `generateWithClonePrompt()`

**Rationale**:
- SwiftVoxAlta is the **orchestration layer** between apps and models
- Drift affects **any** long ICL generation, not just podcasts
- Can be toggled via `GenerationSettings.enableAutoChunking: Bool`
- Keeps Produciesta focused on podcast-specific logic (script parsing, episode assembly)
- Reusable by any app using SwiftVoxAlta (not just Produciesta)

**Implementation Location**:
```
SwiftVoxAlta/Sources/SwiftVoxAlta/VoiceLockManager.swift
```

**API Extension**:
```swift
public struct GenerationSettings {
    // ... existing fields (temperature, topP, repetitionPenalty, maxTokens)
    
    // Sentence chunking settings
    public let enableAutoChunking: Bool = true
    public let chunkTargetDuration: TimeInterval = 10.0  // Max duration per chunk
    public let chunkPauseDuration: TimeInterval = 0.25   // Silence between chunks
}
```

**Implementation Sketch**:
```swift
public static func generateAudio(
    text: String,
    voiceLock: VoiceLock,
    ...
    settings: GenerationSettings
) async throws -> Data {
    
    // 1. Estimate duration
    let estimatedDuration = estimateDuration(text: text)
    
    // 2. Auto-chunk if enabled and text is long
    if settings.enableAutoChunking && estimatedDuration > settings.chunkTargetDuration {
        let chunks = splitAtSentences(text: text, maxDuration: settings.chunkTargetDuration)
        VoiceLockManagerLogger.log("Auto-chunking into \(chunks.count) segments")
        
        var audioChunks: [Data] = []
        for (i, chunk) in chunks.enumerated() {
            // Generate each chunk with same reference (consistent prosody anchor)
            let audio = try await generateSingleChunk(chunk, voiceLock, settings, modelManager, ...)
            audioChunks.append(audio)
            
            // Add natural pause between chunks (except after last)
            if i < chunks.count - 1 {
                audioChunks.append(generateSilence(duration: settings.chunkPauseDuration))
            }
        }
        
        return concatenateAudio(audioChunks)
    } else {
        // Normal single-pass generation (existing path)
        return try await generateSingleChunk(text, voiceLock, settings, modelManager, ...)
    }
}
```

**Pros**:
- ✅ Right abstraction level (orchestration, not app logic or model inference)
- ✅ Reusable across all SwiftVoxAlta clients
- ✅ Configurable per-call via `GenerationSettings`
- ✅ Transparent to Produciesta (no changes needed unless customization desired)
- ✅ Natural place for TTS quality improvements

**Cons**:
- ❌ SwiftVoxAlta needs audio concatenation logic (add WAV utilities to `AudioConversion.swift`)
- ❌ Slightly increases SwiftVoxAlta complexity

---

### Option 2: **Produciesta**

**Placement**: In the narration generation layer (wherever Produciesta calls `VoiceLockManager.generateAudio()`)

**Rationale**:
- Podcast-specific feature
- Full control over chunking strategy per podcast project
- Could use different chunking for different character voices
- Could integrate with Fountain script structure (honor existing action block boundaries)

**Implementation Location**:
```
Produciesta/Sources/ProduciestaCore/Generation/NarrationGenerator.swift (or similar)
```

**Pros**:
- ✅ Podcast-specific customization (chunk differently for dialogue vs. narration)
- ✅ Keeps SwiftVoxAlta simple and focused
- ✅ Can integrate with Fountain screenplay structure

**Cons**:
- ❌ Not reusable for non-podcast SwiftVoxAlta users
- ❌ Produciesta already complex (script parsing, voice design, episode assembly, telemetry)
- ❌ Drift is a **TTS problem**, not a podcast problem — fixing it in the app layer is a leaky abstraction
- ❌ Other apps using SwiftVoxAlta for long-form narration won't benefit

---

## Recommendation: **SwiftVoxAlta**

Implement sentence chunking in **SwiftVoxAlta** because:

1. **Drift is a fundamental ICL TTS problem**, not podcast-specific
2. **SwiftVoxAlta is the right abstraction layer** for "TTS orchestration patterns"
3. **Other apps** using SwiftVoxAlta for long-form narration (audiobooks, meditation scripts, educational content) would benefit
4. **Produciesta stays focused** on podcast domain logic (screenplay parsing, episode structure, character voice design)
5. **Easy to disable** if needed via `GenerationSettings.enableAutoChunking = false`

Produciesta can override chunking settings if needed:
```swift
let customSettings = GenerationSettings(
    temperature: 0.7,
    enableAutoChunking: true,
    chunkTargetDuration: 8.0,  // Shorter chunks for fast-paced dialogue
    chunkPauseDuration: 0.15   // Minimal pause
)
```

---

## Open Design Questions

### 1. **Sentence Detection Strategy**

**Decision (2026-05-09)**: Use Foundation's `String.enumerateSubstrings(options: .bySentences)`.

```swift
var sentences: [String] = []
text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                         options: .bySentences) { substring, _, _, _ in
    if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        sentences.append(s)
    }
}
```

**Rationale**:
- Powered by ICU's `BreakIterator` under the hood. Handles abbreviations (`Dr.`, `Mr.`, `e.g.`), decimals (`3.14`), ellipses, and locale-aware sentence terminators correctly out of the box.
- **Zero new dependencies** — already available wherever Foundation is imported.
- **Strictly better than regex**: same complexity, none of the abbreviation/decimal failure modes. Regex was never the right MVP — Foundation's call is already the simple correct answer.
- Deterministic, synchronous, fast (no model loading).

**Upgrade path (not needed for chunking)**: `NaturalLanguage.NLTokenizer(unit: .sentence)` uses the same ICU backing for sentence boundaries but adds POS tagging, language ID, lemmatization, and sentiment. Reach for this only if GLOSA's Stage Director or VoxAlta telemetry needs token-level analysis — it provides no benefit over Foundation for sentence splitting alone.

**Rejected**: regex-based splitting (`#"[.!?]\s+"#`). It breaks on abbreviations and decimals, and Foundation's call is just as cheap.

---

### 2. **Em-Dash Handling**

**Context**: Chapter 2 analysis identified em-dashes as a prosody hiccup trigger:
> "Em-dashes (smaller, separate factor): Both expositions contain em-dashes... Qwen3-TTS tokenization of `—` is a known mid-utterance prosody hiccup trigger."

**Question**: Should em-dashes be treated as sentence boundaries?

**Option A: Split on Em-Dashes**
```swift
let pattern = #"[.!?—]\s+"#
```

**Pros**:
- Avoids em-dash prosody hiccups
- Creates more chunk boundaries (higher TRIM ratios)

**Cons**:
- Creates very short chunks (may sound choppy)
- "Beauty exists—ugliness defines it" → two 3-word chunks

**Option B: Replace Em-Dashes with Commas**
```swift
let preprocessed = text.replacingOccurrences(of: "—", with: ", ")
let chunks = splitAtSentences(preprocessed)
```

**Pros**:
- Avoids em-dash hiccups without over-chunking
- Preserves natural sentence flow

**Cons**:
- Changes the text semantics slightly

**Option C: Leave Em-Dashes Alone**
- Let adaptive repetition penalty and temperature scaling handle the hiccups
- Em-dashes are a minor contributor compared to anchor dilution

**Recommendation**: Start with **Option C** (ignore em-dashes for chunking). If hiccups persist after adaptive sampling fixes, try **Option B** (replace with commas).

---

### 3. **Audio Concatenation Method**

**Question**: How to concatenate multiple WAV files?

**Option A: Pure Swift WAV Parser**
```swift
// Parse WAV headers, extract PCM data, concatenate, re-wrap
func concatenateAudio(_ chunks: [Data]) throws -> Data {
    var combinedPCM = Data()
    for chunk in chunks {
        let pcm = try AudioConversion.extractPCM(from: chunk)
        combinedPCM.append(pcm)
    }
    return try AudioConversion.wrapPCMInWAV(combinedPCM, sampleRate: 24000)
}
```

**Pros**:
- No dependencies
- Full control

**Cons**:
- Need to implement WAV parsing/writing (if not already present in `AudioConversion.swift`)

**Option B: SwiftFFMpeg**
```swift
// Use ffmpeg concat filter
```

**Pros**:
- Robust, handles any audio format

**Cons**:
- SwiftFFMpeg dependency (check if already in SwiftVoxAlta)
- Overkill for simple WAV concat

**Option C: CoreAudio (AVFoundation)**
```swift
import AVFoundation

func concatenateAudio(_ chunks: [Data]) throws -> Data {
    // Use AVAssetExportSession or AVAudioEngine
}
```

**Pros**:
- Apple's native framework
- Handles format conversion

**Cons**:
- More complex API
- Async callback-based (requires bridging to async/await)

**Decision (2026-05-09)**: Use **Option A** (pure Swift WAV concat). Inspection of `AudioConversion.swift` confirms it already has `buildWAVData(pcmSamples:sampleRate:)` (line 132) and a private `parseFmtAndDataChunks` parser (line 178). Implementation needs only a small public PCM-extractor wrapper plus a `concatenateWAVs([Data])` helper. **No new dependency required.** SwiftFFMpeg and AVFoundation paths are rejected as overkill. See `FIXME-sentence-chunking.md` "Files to Modify" for the exact additions.

---

### 4. **Silence Generation**

**Question**: How to generate 250ms silence between chunks?

**Implementation**:
```swift
private static func generateSilence(duration: TimeInterval) -> Data {
    let sampleRate = 24000  // Match Qwen3-TTS output
    let numSamples = Int(duration * Double(sampleRate))
    let silentSamples = [Int16](repeating: 0, count: numSamples)
    
    // Convert to WAV format
    return AudioConversion.samplesToWAVData(silentSamples, sampleRate: sampleRate)
}
```

**Alternative**: Instead of silence, fade the tail of chunk N into the head of chunk N+1 for smoother transitions. This is more complex and probably not needed for natural sentence pauses.

---

### 5. **Duration Estimation Calibration**

**Current Heuristic** (from Chapter 2 analysis):
```swift
let estimatedSeconds = Double(text.count) * 0.055
```

**Calibration Data**:
- Element 11: 421 chars → 23.12s → 0.055 s/char ✓
- Element 12: 502 chars → 27.12s → 0.054 s/char ✓

**Question**: Is 0.055 s/char accurate across different speaking styles?

**Considerations**:
- Narrator exposition: ~0.055 s/char
- Fast dialogue: ~0.040 s/char (?)
- Slow, dramatic delivery: ~0.070 s/char (?)

**Recommendation**: Start with 0.055 s/char constant. If needed, make it configurable:
```swift
public struct GenerationSettings {
    public let estimatedSecondsPerChar: Double = 0.055
}
```

Or derive it from `temperature` (lower temp → slower speech?). Probably overkill for MVP.

---

## Implementation Roadmap

### Phase 1: Core Chunking (MVP)
1. Add `enableAutoChunking`, `chunkTargetDuration`, `chunkPauseDuration` to `GenerationSettings`
2. Implement `estimateDuration(text:)` with 0.055 s/char heuristic
3. Implement `splitAtSentences(text:maxDuration:)` with regex sentence detection
4. Implement `generateSilence(duration:)` in `AudioConversion.swift`
5. Implement `concatenateAudio([Data])` in `AudioConversion.swift` (pure Swift WAV concat)
6. Modify `VoiceLockManager.generateAudio()` to chunk before generating
7. Add telemetry logging (chunk count, chunk durations, TRIM ratios)

### Phase 2: Testing
1. Re-render Chapter 2 with chunking enabled
2. Verify TRIM ratios > 0.25 for all chunks
3. Verify no prosody drift at 1:30 mark
4. Verify natural pause between sentences
5. Compare against unchunked version (perceptual quality test)

### Phase 3: Refinements (if needed)
1. Upgrade to `NaturalLanguage` tokenizer if abbreviations cause issues
2. Add em-dash → comma preprocessing if hiccups persist
3. Add configurable `estimatedSecondsPerChar` if heuristic is inaccurate
4. Add fade transitions between chunks if hard cuts sound jarring

---

## Files to Modify

### SwiftVoxAlta
1. **`Sources/SwiftVoxAlta/GenerationSettings.swift`**
   - Add `enableAutoChunking: Bool`
   - Add `chunkTargetDuration: TimeInterval`
   - Add `chunkPauseDuration: TimeInterval`

2. **`Sources/SwiftVoxAlta/VoiceLockManager.swift`**
   - Add `estimateDuration(text:) -> TimeInterval`
   - Add `splitAtSentences(text:maxDuration:) -> [String]`
   - Modify `generateAudio(text:voiceLock:...)` to chunk before generating

3. **`Sources/SwiftVoxAlta/AudioConversion.swift`**
   - Add `generateSilence(duration:) -> Data`
   - Add `concatenateAudio([Data]) throws -> Data`
   - Add `extractPCM(from: Data) throws -> Data` (if not present)
   - Add `wrapPCMInWAV(_ pcm: Data, sampleRate: Int) throws -> Data` (if not present)

---

## Success Criteria

- [ ] Long text (>12s) automatically split at sentence boundaries
- [ ] Each chunk has TRIM ratio > 0.25
- [ ] Natural 250ms pause between chunks
- [ ] No prosody drift in long expositions (test with Chapter 2)
- [ ] Short utterances (<12s) pass through unchanged (no unnecessary chunking)
- [ ] Telemetry logs chunk count and durations
- [ ] Can be disabled via `GenerationSettings.enableAutoChunking = false`
- [ ] Produciesta requires no changes (transparent)

---

## Next Steps

**Before Implementation**:
1. ✅ Commit and push adaptive sampling fixes to mlx-audio-swift (DONE)
2. ✅ Ship patch release of mlx-audio-swift (IN PROGRESS)
3. ⏸️  User wants to clear context and change model before tackling chunking

**When Ready**:
1. Review this document
2. Make final decisions on open design questions (sentence detection, em-dash handling, audio concat method)
3. Implement Phase 1 (Core Chunking MVP) in SwiftVoxAlta
4. Test with Chapter 2 generation
5. Refine based on results

---

## References

- **Root cause analysis**: `/Users/stovak/Projects/podcast-tao-de-jing/episodes/chapter_2-findings.md`
- **Full specification**: `/Users/stovak/Projects/SwiftVoxAlta/FIXME-sentence-chunking.md`
- **Related commits**: `mlx-audio-swift` ea8548d (adaptive sampling fixes)
- **Discussion date**: 2026-05-09
