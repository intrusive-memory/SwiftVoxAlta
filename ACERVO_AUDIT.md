# SwiftAcervo Usage Audit — SwiftVoxAlta

**Original audit:** 2026-04-23 (against SwiftAcervo `0.8.0`)
**Re-evaluated:** 2026-04-26 (against SwiftAcervo `0.8.2`)
**Findings 1, 3, 4 closed:** 2026-04-30 (against SwiftAcervo `0.8.4`, shipped in v0.10.0)
**SwiftAcervo dependency pin:** `^0.8.4`
**Reference:** [SwiftAcervo `USAGE.md`](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) (manifest-first contract)

---

## Status snapshot

SwiftVoxAlta uses the **Level 3 (Registered Components)** integration pattern from SwiftAcervo's `USAGE.md` — the correct level for a curated catalog (7 Qwen3-TTS variants with display names, slugs, and memory budgets). All consumer-side findings are resolved as of v0.10.0; the only open item is upstream-blocked.

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | Declared 12-file list is redundant boilerplate | Medium | **Resolved** (v0.10.0) |
| 2 | `withComponentAccess` closure is sync; model load happens outside the access scope (TOCTOU window) | Medium | **Open — blocked upstream** |
| 3 | `AcervoError` cases collapsed into a single `modelNotAvailable` string | Low | **Resolved** (v0.10.0) |
| 4 | App Group entitlement undocumented for downstream consumers | Low (lib), Medium (docs) | **Resolved** (v0.10.0) |
| 5 | `swift-transformers` + `swift-tokenizers` `Tokenizers` target collision blocked SPM resolve | ~~Medium~~ | **Resolved** (2026-04-23) |

**What shipped in v0.10.0:**

- All 7 `ComponentDescriptor`s in `VoxAltaModelManager.swift:131-185` are bare — only `id`, `type`, `displayName`, `repoId`, `minimumMemoryBytes`, and (for the deprecated 4-bit variant) `metadata` are declared. `qwen3TTSRequiredFiles` deleted. Tests in `Tests/SwiftVoxAltaTests/ComponentDescriptorRegistrationTests.swift` assert `descriptor.needsHydration == true` and `descriptor.files.isEmpty` for newly registered descriptors.
- `_loadModelWithComponentValidation` in `VoxAltaModelManager.swift:291-348` performs a full discriminated `catch let error as AcervoError` switch with dedicated arms for `.modelNotFound`, `.integrityCheckFailed`, `.downloadSizeMismatch`, `.componentNotRegistered`, `.componentNotHydrated`, `.offlineModeActive`, `.fileNotInManifest`, `.manifestIntegrityFailed`, and `.manifestDownloadFailed`. The `default` arm catches future cases.
- `AGENTS.md` "App Group entitlement (REQUIRED for app integrators)" section documents the `group.intrusive-memory.models` capability requirement, the silent fallback symptom, per-target setup, and a runtime verification recipe via `Acervo.sharedModelsDirectory`. The `diga` CLI's unsigned-fallback behavior is called out so it isn't mistaken for a bug.

---

## Outstanding items

### Finding 2 — Load inside the `withComponentAccess` scope (Open, blocked upstream)

**Symptom:** `_loadModelWithComponentValidation` exits the `withComponentAccess` closure before calling `TTSModelUtils.loadModel(modelRepo:)`. Between closure exit and the load, another task could (in principle) call `Acervo.deleteModel` on the same id. It's a narrow TOCTOU window.

**Why VoxAlta can't fix this alone:** SwiftAcervo's closure parameter is synchronous — `(ComponentHandle) throws -> T`, not `async throws`. `TTSModelUtils.loadModel` is async. Putting an `await` inside a sync closure is a hard compile error. `withModelAccess` and `withLocalAccess` have the same constraint.

**Path forward, in preference order:**

1. **Upstream feature request to SwiftAcervo** — add an async-closure overload:
   ```swift
   public func withComponentAccess<T: Sendable>(
       _ componentId: String,
       perform: @Sendable (ComponentHandle) async throws -> T
   ) async throws -> T
   ```
   `withModelAccess` should grow the same overload at the same time.
2. **Public lock-acquisition primitives** — `acquireLock(for:)` / `releaseLock(for:)` so consumers can scope a manual `defer` block around an async operation. More flexible but easier to misuse.
3. **Live with the window.** `VoxAltaModelManager` is itself an actor; no in-process caller mutates Acervo's tree concurrently with a load; the validation closure already catches missing-files and checksum-mismatch failure modes. Document the TOCTOU as an accepted risk and move on.

The current code takes path 3 by default. Escalate to path 1 if VoxAlta starts being driven by code that does concurrent `Acervo.deleteModel` calls.

The doc comment on `_loadModelWithComponentValidation` points back to this finding, so a future maintainer hits the right context immediately.

### Optional follow-ups (not regressions; small wins)

These were called out in the original audit's compliance matrix but never blocked release:

- **Disk-space precheck** — `ModelDownloadManager.validateCanDownload(_:)` before `ensureComponentReady`. Memory headroom is checked; disk space currently isn't. Cheapest to add when someone's already in `VoxAltaModelManager.loadModel`.
- **Progress callback on `ensureComponentReady`** — TTS downloads are silent from the user's POV today. If `diga` ever grows a `--progress` flag, that's the moment to wire one up.
- **Verified-offline test** — The cached `loadModel` path returns without touching `ensureComponentReady` on subsequent calls with the same repo, so offline behavior should already work; nobody has added an explicit test that flips `ACERVO_OFFLINE=1` and asserts a typed `.offlineModeActive` failure on cold start. Cheap test, makes a real guarantee testable.

None of these are urgent. Pick them up opportunistically.

---

## Compliance matrix (post-v0.10.0)

| USAGE.md requirement | SwiftVoxAlta status |
|---|---|
| `Package.swift` depends on `SwiftAcervo >= 0.8.0` | ✅ pinned `^0.8.4` |
| App Group `group.intrusive-memory.models` enabled on consuming targets | N/A in this repo (library + unsigned CLI); downstream apps must enable — documented in `AGENTS.md` |
| Use `ensureComponentReady` at startup | ✅ in `VoxAltaModelManager.loadModel` |
| Provide progress feedback via callback | ⚠️ Not wired (silent downloads) — see optional follow-up |
| Handle `AcervoError` cases and convert to app-specific errors | ✅ Full discriminated switch (Finding 3) |
| Call `Acervo.modelDirectory(for:)` / rely on `isModelAvailable` for loading | ✅ `isModelAvailable` used in `isModelInAcervo`; `TTSModelUtils` is the indirection layer |
| Test offline (already-present models load without network) | ⚠️ Not verified; logic should allow it — see optional follow-up |
| Prefer manifest-first APIs over hard-coded file lists | ✅ Bare descriptors (Finding 1) |
| Validate disk space first | ❌ Not done — see optional follow-up |
| Serialize same-model downloads | ✅ `AcervoManager` is an actor; `VoxAltaModelManager` is also an actor |

---

## Finding 5 — `Tokenizers` target collision (resolved, kept for reference)

The original `xcodebuild -resolvePackageDependencies` failure during the v0.7.2 → v0.8.0 bump was:

```
multiple packages ('swift-tokenizers', 'swift-transformers') declare targets with a conflicting name: 'Tokenizers'; target names need to be unique across the package graph
```

**Root cause:** SwiftTuberia v0.4.0 depended on `huggingface/swift-transformers` (which ships its own `Tokenizers` target). The rest of the graph (`mlx-audio-swift`, `SwiftBruja` via `swift-tokenizers-mlx`) already used `DePasqualeOrg/swift-tokenizers` with `traits: ["Swift"]`. Two `Tokenizers` targets in the same graph; SPM refused to resolve.

**Fix:** bumped `SwiftTuberia` `^0.4.0` → `^0.5.0` in `Package.swift`. SwiftTuberia v0.5.0 had already migrated to `DePasqualeOrg/swift-tokenizers` (Swift trait), matching the Bruja stack. Six transitive packages dropped out of the graph (`swift-transformers`, `swift-huggingface`, `eventsource`, `swift-nio`, `swift-atomics`, `swift-system`).

**Why it's worth keeping in the audit:** the same pattern can re-trigger. If another sibling library bumps a dependency that pulls `huggingface/swift-transformers` back into the graph, SPM resolution will fail with the exact error above. The fix is always the same: trace which sibling package introduced `swift-transformers`, push it to use `DePasqualeOrg/swift-tokenizers` with the Swift trait, ship that release, then bump VoxAlta.

**Rust backend status:** `DePasqualeOrg/swift-tokenizers` ships a `TokenizersRust` xcframework target behind the `Rust` trait. No consumer in the SwiftVoxAlta graph sets that trait (every consumer passes `traits: ["Swift"]`), so the Rust binary is never resolved or downloaded. This matches the Bruja convention.

---

## Original-audit history

The pre-resolution analysis (file-list quotes, the v0.7-era patterns, the recommendation diffs that became Findings 1–4) lived in this file through 2026-04-30. It was removed when the findings shipped because the post-resolution code no longer matches those quotes — keeping them inline produced a "this audit contradicts the source" hazard for readers. The git history at and before commit `57fe23f` preserves the full pre-trim text if you ever need to reconstruct the rationale for the original recommendations.
