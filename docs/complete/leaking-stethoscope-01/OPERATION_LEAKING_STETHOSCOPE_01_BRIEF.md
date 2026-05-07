# Iteration 01 Brief — OPERATION LEAKING STETHOSCOPE

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. A *brief* is the post-mission review that harvests lessons before the next iteration.

**Mission:** Add a pluggable telemetry pipeline to SwiftVoxAlta so external consumers can prove whether `unloadModel()` actually frees memory and whether the voice cache leaks across episodes — gated behind an empirical preflight probe.
**Branch:** `feature/telemetry-instrumentation`
**Starting Point Commit:** `b8fd93a` (Mark development as 0.10.3-dev)
**Final Commit:** `eb25d90` (Sortie 8: E2E contract test + telemetry docs)
**Sorties Planned:** 8 (1 preflight + 7 implementation)
**Sorties Completed:** 8 of 8
**Sorties Failed/Blocked:** 0 (Sortie 1 took 3 attempts; rest first-pass)
**Duration:** Single working day, 2026-05-06.
**Outcome:** Complete
**Verdict:** **Keep the code.** The telemetry pipeline is built, tested, documented, and ready to merge — even though the mission's original premise (`unloadModel()` leaks) was empirically falsified by Sortie 1. The artifacts now serve as production observability infrastructure to localize the real leak in the next mission.

---

## 1. Hard Discoveries

### 1. SwiftVoxAlta's `unloadModel()` does not leak

**What happened:** Sortie 1 escalated through three probe variants (single-cycle 500 ms drain → single-cycle 2 s drain → 3-cycle marginal-average). The first two returned INCONCLUSIVE because `netDelta ≈ 340 MB` straddled the LEAK / NO LEAK thresholds. The 3-cycle variant proved the residual was structural one-time MLX/Metal initialization, not progressive growth: d1 = 340.28 MB, d2 = 18.70 MB, d3 = 4.77 MB, marginalAvg = 11.73 MB (well below the 50 MB NO LEAK threshold).
**What was built to handle it:** `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift` with the 3-cycle marginal-average algorithm. Gated behind `VOXALTA_RUN_LEAK_PROBE=1`. Wrapped in `make test-leak-probe` Makefile target.
**Should we have known this?** No. The premise was reasonable from Produciesta's symptoms; the empirical falsification was the whole point of Sortie 1.
**Carry forward:** The leak Produciesta sees does **not** live in SwiftVoxAlta's model lifecycle. The next mission should instrument other libraries (SwiftHablare, mlx-audio-swift, Tuberia, the adapter layer) using the telemetry pattern landed here.

### 2. First-cycle MLX/Metal init costs ~340 MB and never returns

**What happened:** Even after `unloadModel()` + `clearGPUCache()` + 2 s drain, ~340 MB stays resident in the xctest process. Cycles 2 and 3 add only 4–18 MB each. This is structural framework overhead, not a defect.
**What was built to handle it:** Verdict thresholds shifted from raw `netDelta` (which conflates structural and progressive) to `marginalAvg` of cycles 2–N (which isolates per-cycle retention).
**Should we have known this?** Probably yes — MLX docs hint at framework warm-up costs but don't quantify. A literature pass before the mission would have biased the spec toward multi-cycle math from the start.
**Carry forward:** Any future memory probe in this ecosystem MUST use marginal-average across ≥3 cycles. Single-cycle deltas are misleading by ~340 MB.

### 3. macOS 26 sandbox blocks `xcodebuild test` → Acervo metadata writes

**What happened:** Sortie 1's post-conversion attempt to run the probe via `make test-leak-probe` (standard `xcodebuild test` pipeline) failed with "You don't have permission to save the file 'README.md' in the folder 'mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16'". The `.acervoEnvironment` Swift Testing trait correctly bootstrapped `ACERVO_APP_GROUP_ID` and the sentinel-file gate worked, but Acervo's `ensureComponentReady()` writes model metadata to `~/Library/Group Containers/`, which xcodebuild's macOS 26 sandbox blocks for xctest processes.
**What was built to handle it:** Probe still ships, runnable via direct xctest binary invocation (functionally equivalent for RSS deltas). Tests that only **read** from Acervo (or don't touch the model cache) work fine via `make test-leak-probe`.
**Should we have known this?** No — this is a macOS 26-specific platform restriction, surfaced only by collision.
**Carry forward:** Tests that need Acervo's model-cache **write** path cannot run inside `xcodebuild test`. Either run via direct xctest, or pre-stage the cache outside the sandbox. Document in `docs/BUILDING.md` if other libraries adopt the same pattern.

### 4. `VoxAltaVoiceProvider` is `final class @unchecked Sendable`, not an actor

**What happened:** The original spec for Sortie 4 assumed the provider was an actor and called `setTelemetry` synchronously. Pass 4 refinement caught this against the source and corrected to `async` forwarding to the actor `modelManager`. Refinement saved a build break.
**What was built to handle it:** `setTelemetry(_:)` and `capture(_:)` on the provider are both `async` and forward to `modelManager`. The provider's mutable telemetry state lives inside the actor.
**Should we have known this?** Yes — readme/grep would have caught it. Add a "verify actor-vs-class for every type touched" step to refinement Pass 4 in `mission-supervisor`.
**Carry forward:** Anywhere the next mission instruments a non-actor type, the setter pattern stays `async` and forwards to whichever actor owns the state.

### 5. `mlx-swift` public API has no peak Metal heap counter

**What happened:** Sortie 7's research probe found `MLX.GPU.activeMemory` (or equivalent) reachable for current allocation but no public peak counter. The plan's `-1` fallback policy absorbed this without a sortie split.
**What was built to handle it:** `MLXRetentionReport.metalHeapSizeMB` reports current allocation; `metalBufferState.peakMB` always emits `-1.0` with an inline `// peak unavailable from public MLX API` comment. Documented as a known limitation in `docs/telemetry.md`.
**Should we have known this?** No — required source spelunking inside the mlx-swift fork.
**Carry forward:** If peak tracking becomes essential for Produciesta-side leak localization, file an upstream PR or maintain a fork-local computed peak (sample on every event and `max()`).

---

## 2. Process Discoveries

### What the Agents Did Right

#### 1. Empirical preflight gate

**What happened:** Sortie 1 executed before any of Sorties 2–8 wrote a line of telemetry code. Three probe variants resolved a definitive verdict.
**Right or wrong?** Right. The gate cost ~1 hour of dispatches and produced certainty about the problem domain that no amount of code would have delivered.
**Evidence:** Plan estimated Sortie 1 at 60–120 s; actual was ~30 min across 3 attempts. Spent ~30 min total to confirm the next 7 sorties were aimed at the right problem (telemetry as observability) rather than the wrong one (leak fixing).
**Carry forward:** Every mission whose premise depends on a measurable property of the system should have a preflight falsification sortie. **This is the strongest pattern from the mission and should be elevated to a mission-supervisor convention.**

#### 2. Pass 4 auto-fixes were comprehensive

**What happened:** Pass 4 of refinement caught and corrected 9 issues before execution: vague test seams, wrong access modifiers, non-deterministic formulas, oversized test-suite invocations, premise-unverified gating.
**Right or wrong?** Right. Zero of those 9 issues caused execution-time rework.
**Evidence:** Sorties 2–8 all completed on first attempt. The only retries were Sortie 1, and those were premise-falsification escalations, not bug fixes.
**Carry forward:** Refinement passes pay for themselves. Don't skip them under time pressure.

#### 3. Sortie sizing was correct

**What happened:** All 8 sorties fit within their context budgets without splits or merges.
**Right or wrong?** Right.
**Evidence:** Average sortie size ~22 turns vs 50-turn budget. No sortie hit BACKOFF for context-window exhaustion.
**Carry forward:** The 22-turn target is durable for telemetry-style work in this codebase. Use as a baseline for the next instrumentation mission.

### What the Agents Did Wrong

#### 4. Sortie 1's first attempt used 500 ms drain when 2 s was already documented as the fallback

**What happened:** The plan specified 500 ms drain and listed 2 s in Known Risks as the escalation. The first dispatch used 500 ms, returned INCONCLUSIVE, and required a re-dispatch with 2 s.
**Right or wrong?** Wrong. If 2 s was already pre-authorized in Known Risks, the first attempt should have used it.
**Evidence:** One full Sortie 1 dispatch wasted on a known-marginal drain window. Cost: ~10 min wall clock.
**Carry forward:** When a plan's Known Risks pre-authorizes a more conservative parameter, start there. Don't burn a dispatch to re-discover the documented risk.

### What the Planner Did Wrong

#### 5. The decision gate had no escalation path for INCONCLUSIVE → 3-cycle

**What happened:** The plan's verdict table listed three actions: LEAK SUSPECTED → proceed, NO LEAK → pause, INCONCLUSIVE → pause. There was no "INCONCLUSIVE → escalate to 3-cycle marginal-average and re-run before pausing" branch. The supervisor invented it on the fly under user direction.
**Right or wrong?** Wrong. The 3-cycle algorithm is the correct discriminator between structural and progressive growth, and it should have been pre-specified.
**Evidence:** Two INCONCLUSIVE verdicts (single-cycle 500 ms; single-cycle 2 s) before the supervisor escalated to 3-cycle. Both pauses required user input that a properly-specified plan would have automated.
**Carry forward:** Decision gates with thresholds must include the next probe variant for every ambiguous verdict. "Pause on INCONCLUSIVE" is not enough — say what the next probe should look like.

#### 6. Group 3 spec'd Sortie 5 ‖ Sortie 6 as parallel, but xcodebuild contention forced sequentialization

**What happened:** EXECUTION_PLAN.md Group 3 specified Sortie 5 and Sortie 6 as parallel because they touch disjoint source files. The supervisor sequentialized them to avoid concurrent `make build` against the same DerivedData.
**Right or wrong?** Right call by the supervisor (xcodebuild lock contention is real); wrong assumption by the planner (file-disjointness is necessary but not sufficient for parallelism in xcodebuild projects).
**Evidence:** ~5 min of wall-clock parallelism foregone. Zero diagnosis cost.
**Carry forward:** Refinement Pass 3 (parallelism) must check tool-level contention (DerivedData locks, simulator slots, model-cache writes), not just file-level disjointness.

#### 7. The mission was framed as "prove the leak" instead of "build observability"

**What happened:** The plan's primary framing was leak-detection. After Sortie 1 falsified the premise, the user explicitly re-framed the mission as observability infrastructure. The remaining 7 sorties shipped under the new framing.
**Right or wrong?** Wrong framing in the original plan, recovered by user direction at the decision gate.
**Evidence:** A `git log` and `git diff` showing all 7 implementation sorties produce code that has zero ties to the original premise — they're pure telemetry plumbing, useful regardless of where the leak lives.
**Carry forward:** Telemetry/observability missions should be framed as "instrument these specific call sites for these specific consumers" — premise-independent. If a falsification gate is needed, run it as a separate mission, not Sortie 1 of an instrumentation mission.

---

## 3. Open Decisions

### 1. Where does the leak Produciesta sees actually live?

**Why it matters:** The whole reason for this telemetry is to localize the leak. SwiftVoxAlta is now ruled out. The next mission cannot start without a target list.
**Options:**
- (A) SwiftHablare's voice provider registry / cross-provider cache
- (B) mlx-audio-swift internal model retention (the upstream fork)
- (C) Tuberia (audio pipeline) buffer accumulation
- (D) Produciesta's `VoxAltaTelemetryAdapter` itself (retain cycle in callback closures)
- (E) Multi-component interaction (leak emerges only when ≥2 of the above interact across episode boundaries)
**Recommendation:** Instrument (A), (B), and (D) in parallel sub-missions, each using the pattern landed here. Hold (C) until events from (A)+(B)+(D) narrow the suspect.

### 2. Should the preflight probe pattern be promoted to shared tooling?

**Why it matters:** If we instrument SwiftHablare, mlx-audio-swift, and Tuberia next, each will need its own probe. Copy-pasting `PreflightLeakProbeTests.swift` 3× is fine; building a shared test fixture or trait is better.
**Options:**
- (A) Copy-paste per repo. Simple, fast, divergence is OK.
- (B) Extract a `MemoryProbeKit` package. Reusable but takes a sortie of its own.
- (C) Add it to SwiftAcervo or a new `intrusive-memory/swift-memory-probe` package alongside `.acervoEnvironment`.
**Recommendation:** (A) for the next mission; revisit for (B) or (C) if a third repo needs it.

### 3. Produciesta-side adapter: blocking next mission?

**Why it matters:** All this telemetry is dead capacitance until Produciesta wires up a `VoxAltaTelemetryReporter` implementation that streams events to its observability sink. The contract test in Sortie 8 proves the shape; it does not produce the implementation.
**Options:**
- (A) Build the Produciesta adapter as a follow-up mission in this repo (out of scope, would need consumer-repo write access).
- (B) Drop a stub adapter in Produciesta's repo and let that team finish it.
- (C) Document the contract in `docs/telemetry.md` (already done in Sortie 8) and treat as Produciesta's responsibility.
**Recommendation:** (C). The contract is documented; Produciesta owns the wiring. Coordinate via PR comment, not a SwiftVoxAlta sortie.

---

## 4. Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Preflight leak probe (single-cycle, 500 ms) | sonnet | 1 of 3 | Partial | INCONCLUSIVE — drain too short. Documented Known Risk, should have been started at 2 s. |
| 1 (rerun) | Probe with 2 s drain | sonnet | 2 of 3 | Partial | INCONCLUSIVE — single-cycle math conflates structural overhead with progressive leak. |
| 1 (3-cycle) | Probe with 3-cycle marginal-average | sonnet | 3 of 3 | Yes | Definitive NO LEAK verdict. Algorithm change made the prior two attempts retroactively useful as scaffolding. |
| 1 (post) | Convert probe to Swift Testing + Makefile target | sonnet | 1 | Yes | Surfaced macOS 26 sandbox limitation as a hard discovery; preserved direct-xctest path. |
| 2 | Telemetry foundation types | sonnet | 1 | Yes | All 5 files, no rework. Equatable round-trip test caught early. |
| 3 | Memory measurement helpers | sonnet | 1 | Yes | Test-seam pattern (`_setCurrentModelRepoForTesting`) clean. |
| 4 | Telemetry property + setter + capture helper | sonnet | 1 | Yes | Provider's `final class` correctness preserved; `async` forwarding works. |
| 5 | Instrument loadModel/unloadModel | sonnet | 1 | Yes | Deterministic `freed` formula; no actor-reentrancy regression. |
| 6 | Voice cache reportState + growth events | sonnet | 1 | Yes | Plan called for sub-agent; supervisor handled directly to dodge Group 3 contention. Right call. |
| 7 | MLX retention + Metal probe | sonnet | 1 | Yes | `-1` fallback policy worked; event still fires as documented. |
| 8 | E2E contract test + docs | sonnet | 1 | Yes | All exit criteria met; `docs/telemetry.md` and `AGENTS.md` updated. |

**Accuracy summary:** 8 of 8 sorties produced output that survived into the final state without rework. The 3 Sortie 1 attempts are an honest retry pattern, not waste — each attempt produced data that informed the next. **Net: zero discarded work.**

---

## 5. Harvest Summary

We now know SwiftVoxAlta's `unloadModel()` is **not** the leak. We have a working public telemetry pipeline (`VoxAltaTelemetryEvent`, `VoxAltaTelemetryReporter`, `VoiceCacheTelemetry`, `MLXRetentionReport`, `getCurrentProcessMemory`) wired into every model-lifecycle and cache-mutation site, plus a callable preflight probe with a 3-cycle marginal-average verdict algorithm that distinguishes structural framework overhead from progressive retention. The single most important thing that changes about the next iteration: **the leak hunt moves to the other libraries in the puzzle (SwiftHablare, mlx-audio-swift, the Produciesta adapter) using the same instrumentation pattern landed here**, and every future memory probe in this ecosystem starts with multi-cycle math, not single-cycle deltas.

---

## 6. Files

### Preserve (read-only reference for next iteration)

| File | Branch | Why |
|------|--------|-----|
| `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryEvent.swift` | `feature/telemetry-instrumentation` | Public event enum — the contract surface for consumers |
| `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryReporter.swift` | `feature/telemetry-instrumentation` | Public reporter protocol |
| `Sources/SwiftVoxAlta/Telemetry/VoxAltaTelemetryTypes.swift` | `feature/telemetry-instrumentation` | `VoiceCacheTelemetry`, `MLXRetentionReport`, `TopVoice` |
| `Sources/SwiftVoxAlta/Telemetry/ProcessMemory.swift` | `feature/telemetry-instrumentation` | `getCurrentProcessMemory()` — pattern for next mission's probes |
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` (telemetry hooks) | `feature/telemetry-instrumentation` | Reference instrumentation pattern for actor types |
| `Sources/SwiftVoxAlta/VoxAltaVoiceProvider.swift` (telemetry forwarding) | `feature/telemetry-instrumentation` | Reference pattern for non-actor types |
| `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift` | `feature/telemetry-instrumentation` | 3-cycle marginal-average probe template — copy/adapt for other repos |
| `Tests/SwiftVoxAltaTests/Telemetry/MockTelemetryReporter.swift` | `feature/telemetry-instrumentation` | Test reporter shape — copy/adapt |
| `docs/telemetry.md` | `feature/telemetry-instrumentation` | Public API doc — extend, don't replace, in next mission |
| `Makefile` (`test-leak-probe` target) | `feature/telemetry-instrumentation` | Pattern for `make` targets that gate behind env vars |
| `EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md` (archived) | `feature/telemetry-instrumentation` | Reference for Pass 4 auto-fix patterns and decisions log |

### Discard (will not exist after rollback)

| File | Why it's safe to lose |
|------|------------------------|
| _none_ | The verdict is **keep the code**, not discard. No rollback ritual. All artifacts are preserved or archived; nothing in this mission needs to disappear. |

---

## 7. Iteration Metadata

**Starting point commit:** `b8fd93a` (Mark development as 0.10.3-dev)
**Mission branch:** `feature/telemetry-instrumentation`
**Final commit on mission branch:** `eb25d90` (Sortie 8: E2E contract test + telemetry docs)
**Rollback target:** _N/A — verdict is "keep the code, not iterate". Mission proceeds via PR to `development` → `main`._
**Next iteration branch:** _N/A for this operation. The next mission ("instrument other libraries to localize the leak") is a **separate mission**, not Iteration 02 of this one._

**Landing path (per user instruction):**
1. `feature/telemetry-instrumentation` → PR to `development`
2. `development` → PR to `main`
3. Tag release on `main` per repo convention (`/ship-swift-library`)

The mission branch is preserved locally for reference until merged.

---

## Notes

- This brief was generated from `EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md` decisions log, `LEAK_PROBE_RESULT.md`, and `git log b8fd93a..eb25d90`.
- The next mission should start with the open decisions in §3 resolved, particularly which libraries to instrument first.
- The empirical preflight gate pattern (Sortie 1) is the single most valuable methodology import from this mission. Carry it forward.
