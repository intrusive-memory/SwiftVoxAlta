# SwiftAcervo Usage Audit — SwiftVoxAlta

**Original audit:** 2026-04-23 (against SwiftAcervo `0.8.0`)
**Re-evaluated:** 2026-04-26 (against SwiftAcervo `0.8.2`)
**SwiftAcervo dependency bumped:** `0.7.2` → `0.8.0` → `0.8.2`
**Reference:** [SwiftAcervo `USAGE.md`](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) (manifest-first contract)

---

## Summary

SwiftVoxAlta uses the **Level 3 (Registered Components)** integration pattern from `USAGE.md`. That is the correct level for a curated-catalog library like this one (7 Qwen3-TTS variants with display names, slugs, and memory budgets).

The audit's recommendations have not been implemented yet — the four open findings below all still describe the current state of `Sources/SwiftVoxAlta/VoxAltaModelManager.swift`. Nothing on the SwiftAcervo side has shifted the target: 0.8.1 was a pure additive release (offline-mode env-var gate, see §0 below) and 0.8.2 was CI/test-stability with no public API changes. The recommended pattern remains exactly what's described here.

| Finding | Severity | Status | Action |
|---|---|---|---|
| Declared 12-file list is now redundant boilerplate | Medium | **Open** | Drop `files:` / `estimatedSizeBytes` from all 7 `ComponentDescriptor`s; let the manifest hydrate on first use |
| `withComponentAccess` closure is a no-op; model load happens outside the access scope (TOCTOU window) | Medium | **Blocked (upstream)** | The closure is sync (`(ComponentHandle) throws -> T`); the async load can't go inside it. Needs an async-closure overload of `withComponentAccess` in SwiftAcervo before VoxAlta can close the window |
| `AcervoError` cases collapsed into a single `modelNotAvailable` string | Low | **Open** | Switch on `AcervoError` (now including `.offlineModeActive` from 0.8.1) to produce actionable messages |
| App Group entitlement (`group.intrusive-memory.models`) undocumented for downstream consumers | Low (library), Medium (docs) | **Open** | Add a note to `AGENTS.md` so app consumers know they must enable this capability |
| `swift-transformers` + `swift-tokenizers` `Tokenizers` target collision blocked `xcodebuild -resolvePackageDependencies` | ~~Medium~~ | **Resolved** (2026-04-23) | Bumped `SwiftTuberia` `^0.4.0` → `^0.5.0`; v0.5.0 had already migrated to `DePasqualeOrg/swift-tokenizers` with the Swift trait, matching the Bruja stack |

---

## 0. What's new since the original audit (0.8.1 + 0.8.2)

The audit was written against 0.8.0. Two patch releases have shipped since; only one of them is consumer-visible.

### 0.8.1 — `ACERVO_OFFLINE` env-var gate

- New env var: `ACERVO_OFFLINE=1` makes every CDN-touching path throw `AcervoError.offlineModeActive` instead of fetching. Local-only paths (`Acervo.modelDirectory(for:)`, `Acervo.isModelAvailable(_:)`, `withModelAccess`, `LocalHandle`, hydrate-from-cache) are unaffected.
- New `AcervoError` case: `.offlineModeActive`. Should be added to the error switch in **Finding 3** when that finding is implemented.
- Useful for SwiftVoxAlta tests that need to assert "no network" without mocking — flip the env var, expect the typed error.

### 0.8.2 — CI/test stability, no API change

- Maintenance-only release. `actions/checkout` v6, two test-suite race fixes, manifest tamper coverage, multi-file rollback coverage. No public API changes; no migration work.

### Consequence for this audit

Findings 1, 2, 3, and 4 are unchanged in target shape. Finding 3's switch should pick up `.offlineModeActive` as an additional case.

---

## 1. Reference pattern (SwiftAcervo v0.8.0 `USAGE.md`)

The v0.8.0 contract in one sentence: **a consumer does not know what files exist inside a model until the CDN manifest comes back — build for the manifest-first flow; fall back to pinning a file subset only when you genuinely need to.**

Three consumption levels:

- **Level 1 — Batch.** `ModelDownloadManager.shared.ensureModelsAvailable([ids])` — apps with simple "download these N models" needs.
- **Level 2 — Single-model manifest-first.** `Acervo.ensureAvailable(modelId, files: [])` — `[]` means "the whole manifest."
- **Level 3 — Registered components.** `Acervo.register(descriptor)` → `Acervo.ensureComponentReady(id)` — for libraries that expose a curated catalog with display names / memory budgets / metadata. **This is SwiftVoxAlta's level.**

The v0.8.0 change inside Level 3: the **bare** `ComponentDescriptor` (no `files:`, no `estimatedSizeBytes`) is now the recommended default. `ensureComponentReady` auto-hydrates the descriptor from the CDN manifest on first call. Pinning a specific file subset is still supported as an escape hatch, but it's no longer the default shape.

New v0.8.0 surface worth knowing about:

- `Acervo.hydrateComponent(id)` — populate the registered descriptor from the CDN manifest without downloading bytes. Useful for a model picker that needs sizes.
- `Acervo.fetchManifest(for: modelId)` / `Acervo.fetchManifest(forComponent: id)` — raw manifest by repoId or registered id.
- `Acervo.isComponentReadyAsync(id)` — readiness check that hydrates a bare descriptor first (the sync `isComponentReady` returns `false` for un-hydrated descriptors).
- `Acervo.unhydratedComponents()` — enumerate pending-hydration ids.
- `ComponentDescriptor.isHydrated` / `needsHydration` — discriminate declared-up-front from registry-pending.
- `AcervoError.componentNotHydrated(id:)` — thrown from sync-only paths when the descriptor still has no file list.

---

## 2. Current usage in SwiftVoxAlta

All SwiftAcervo surface area is in one file:

- `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` — `import SwiftAcervo`, registration, download, validation, load.
- `Tests/SwiftVoxAltaTests/ComponentDescriptorRegistrationTests.swift` — registry assertions (read-only).

`Sources/diga/*.swift` does **not** import SwiftAcervo directly; it goes through `VoxAltaModelManager`. Clean.

### 2.1 Registration (`VoxAltaModelManager.swift:130-227`)

```swift
private let qwen3TTSRequiredFiles: [ComponentFile] = [
  ComponentFile(relativePath: "config.json"),
  ComponentFile(relativePath: "generation_config.json"),
  ComponentFile(relativePath: "preprocessor_config.json"),
  ComponentFile(relativePath: "tokenizer_config.json"),
  ComponentFile(relativePath: "vocab.json"),
  ComponentFile(relativePath: "merges.txt"),
  ComponentFile(relativePath: "model.safetensors"),
  ComponentFile(relativePath: "model.safetensors.index.json"),
  ComponentFile(relativePath: "speech_tokenizer/config.json"),
  ComponentFile(relativePath: "speech_tokenizer/configuration.json"),
  ComponentFile(relativePath: "speech_tokenizer/model.safetensors"),
  ComponentFile(relativePath: "speech_tokenizer/preprocessor_config.json"),
]

private let qwen3TTSComponentDescriptors: [ComponentDescriptor] = [
  ComponentDescriptor(
    id: Qwen3TTSModelRepo.base1_7B.componentId,
    type: .languageModel,
    displayName: "Qwen3-TTS Base 1.7B (bf16)",
    repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
    files: qwen3TTSRequiredFiles,
    estimatedSizeBytes: 3_400_000_000,
    minimumMemoryBytes: 3_400_000_000
  ),
  // …6 more identical-shaped descriptors…
]

private let _registerQwen3TTSComponents: Void = {
  Acervo.register(qwen3TTSComponentDescriptors)
}()
```

**Status vs v0.8.0 reference:** this is the v0.7-era "declared file list" form. USAGE.md calls out the equivalent form as "still supported" but notes:

> Equivalent form using a registered `ComponentDescriptor` with a declared file list (the v0.7-era pattern, still supported).

Since every variant declares the **same** 12-file list and the actual files match the CDN manifest (they're the full Qwen3-TTS shape), there is no subset being pinned — this is exactly the case the new bare descriptor was designed for.

### 2.2 Download + load (`VoxAltaModelManager.swift:368-422`)

```swift
public func loadModel(repo: String) async throws -> any SpeechGenerationModel {
    migrateIfNeeded()

    if let cached = cachedModel, _currentModelRepo == repo { return cached }
    if cachedModel != nil { await unloadModel() }

    guard let modelRepo = Qwen3TTSModelRepo(rawValue: repo) else {
        throw VoxAltaError.modelNotAvailable("Unknown Qwen3-TTS repository: '\(repo)'")
    }

    let componentId = modelRepo.componentId

    if let descriptor = Acervo.component(componentId) {
        await checkMemory(forModelSizeBytes: Int(descriptor.minimumMemoryBytes))
    }

    // Step 1: download via Component Registry.
    try await Acervo.ensureComponentReady(componentId)

    // Step 2: load with "validated" access.
    let model = try await _loadModelWithComponentValidation(
        componentId: componentId, repo: repo
    )
    …
}
```

**Status vs reference:** `ensureComponentReady(componentId)` is the exact pattern USAGE.md recommends for Level 3. ✅

### 2.3 Validation closure (`VoxAltaModelManager.swift:319-351`)

```swift
private func _loadModelWithComponentValidation(
    componentId: String, repo: String
) async throws -> any SpeechGenerationModel {
    do {
        try await AcervoManager.shared.withComponentAccess(componentId) { @Sendable _ in
            // Validation happens on closure entry (file presence + checksums if defined).
            // We don't need to use the handle for file operations since TTSModelUtils
            // will access the Acervo-managed directory directly.
            ()
        }
    } catch {
        throw VoxAltaError.modelNotAvailable(
            "Failed to validate model component '\(componentId)': \(error.localizedDescription)"
        )
    }

    // After validation succeeds, load the model via TTSModelUtils.
    // Files are guaranteed to exist and be valid at this point.
    let model = try await TTSModelUtils.loadModel(modelRepo: repo)
    …
}
```

**Status vs reference:** USAGE.md positions `withModelAccess` / `withComponentAccess` as scoped-exclusive-access primitives:

> Use `withModelAccess` when you need exclusive access to a model directory while reading — no other task can download or mutate that directory while the closure is running.

The current code uses the closure only as a validation side-effect, then calls `TTSModelUtils.loadModel` **outside** that scope. Between the closure exit and the load, another task could (in principle) call `Acervo.deleteModel` on the same id. It's a narrow TOCTOU window for a system this size, but the whole point of the scoped access primitive is to close exactly that window.

Also the comment "Files are guaranteed to exist and be valid at this point" is only true *at closure exit* — it's not true at the `TTSModelUtils.loadModel` call site outside the closure.

### 2.4 Other surface

- `isModelInAcervo(_:)` → `Acervo.isModelAvailable(modelId)` — matches USAGE.md's "local validity marker" semantics (`config.json` presence). ✅
- `migrateIfNeeded()` → `Acervo.migrateFromLegacyPaths()` — documented path, still current in 0.8.0. ✅
- Memory budget lookup → `Acervo.component(componentId)?.minimumMemoryBytes` — correct; works for both hydrated and declared-up-front descriptors. ✅

### 2.5 Tests (`Tests/SwiftVoxAltaTests/ComponentDescriptorRegistrationTests.swift`)

Tests assert structural invariants of the registered descriptors (id, type, repoId, displayName, `estimatedSizeBytes > 0`, `minimumMemoryBytes > 0`, `files.count >= 12`, deprecated flag). These are pure-metadata assertions — no network, no file I/O.

**Status vs reference:** if the registration is migrated to bare descriptors (finding #1 below), three of these assertions change meaning:

- `descriptor.files.count >= 12` — will be `0` before hydration, `12` after. Either drop the assertion or replace with `descriptor.needsHydration == true` pre-hydration.
- `descriptor.estimatedSizeBytes > 0` — will be `0` before hydration. Drop or replace with a post-hydration check.
- `descriptor.estimatedSizeBytes == 3_400_000_000` (the hard-coded expectation in `base17BSizeMatchesExpectation`) — becomes "whatever the manifest says." If the test is valuable as a manifest-drift guard, move it to an integration test that calls `Acervo.hydrateComponent(_:)` first.

---

## 3. Findings

### Finding 1 — Adopt bare `ComponentDescriptor` (recommended default in v0.8.0+) — **Open**

**Current:** each of the 7 descriptors declares a 12-file list and an `estimatedSizeBytes`. Both fields duplicate what the CDN manifest will authoritatively say; if the published model ever changes shape (a new file, a renamed tokenizer), the declared list drifts and SwiftAcervo emits a drift warning and uses the manifest anyway.

**Recommendation:** register bare descriptors. Keep `minimumMemoryBytes` (it's a VoxAlta policy decision, not model metadata) and keep `metadata: ["deprecated": "true"]`.

```swift
private let qwen3TTSComponentDescriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
        id: Qwen3TTSModelRepo.base1_7B.componentId,
        type: .languageModel,
        displayName: "Qwen3-TTS Base 1.7B (bf16)",
        repoId: Qwen3TTSModelRepo.base1_7B.rawValue,
        minimumMemoryBytes: 3_400_000_000
    ),
    // …6 more…
]
```

**Delete:** `qwen3TTSRequiredFiles` (lines 130-143).
**Update:** the registration tests per §2.5 above.

**Tradeoff worth naming:** pre-hydration, `descriptor.estimatedSizeBytes == 0` and `descriptor.files.isEmpty`. Any UI that wants a size before first download must call `Acervo.hydrateComponent(id)` explicitly (or `fetchManifest(forComponent:)`). SwiftVoxAlta currently does not have such UI — diga downloads on demand — so this is a no-op for callers today.

### Finding 2 — Load inside the `withComponentAccess` scope — **Blocked (upstream)**

**Current:** `_loadModelWithComponentValidation` exits the access closure, then calls `TTSModelUtils.loadModel(modelRepo: repo)` outside it. The handle parameter is deliberately ignored (`@Sendable _ in ()`).

**Why this can't be implemented today:** verified against SwiftAcervo 0.8.2's `AcervoManager.swift:430`:

```swift
public func withComponentAccess<T: Sendable>(
    _ componentId: String,
    perform: @Sendable (ComponentHandle) throws -> T
) async throws -> T
```

The closure is **synchronous** (`(ComponentHandle) throws -> T`, not `async throws`). `TTSModelUtils.loadModel` is async. Putting an `await` call inside a sync closure is a hard compile error — `Cannot pass function of type '@Sendable (ComponentHandle) async throws -> any SpeechGenerationModel' to parameter expecting synchronous function type`. `withModelAccess` and `withLocalAccess` have the same constraint.

**What this means:** the original audit recommendation is not implementable as-stated. The TOCTOU window between closure exit and the async `TTSModelUtils.loadModel` call cannot be closed by VoxAlta alone.

**Path forward** (one of):

1. **Upstream feature request to SwiftAcervo:** add an async-closure overload —

   ```swift
   public func withComponentAccess<T: Sendable>(
       _ componentId: String,
       perform: @Sendable (ComponentHandle) async throws -> T
   ) async throws -> T
   ```

   This is the cleanest path; `withModelAccess` should grow the same overload at the same time.

2. **Public lock acquisition primitives:** expose `acquireLock(for:)` / `releaseLock(for:)` so consumers can scope a manual `defer` block around an async operation. More flexible but harder to misuse.

3. **Live with the window.** In practice, VoxAltaModelManager is itself an actor, no in-process caller mutates Acervo's directory tree concurrently with a load, and the validation closure already catches the failure modes that matter (missing files, checksum mismatches). Document the TOCTOU as a known acceptable risk and move on.

The current code takes path 3 by default and adds a doc comment pointing at this finding. If VoxAlta starts being driven by code that does concurrent `Acervo.deleteModel` calls, escalate to path 1.

### Finding 3 — Discriminate `AcervoError` cases in error translation — **Open**

**Current:** both the `withComponentAccess` failure and the `TTSModelUtils.loadModel` failure collapse into the same `VoxAltaError.modelNotAvailable(stringified-error)` bucket. A SHA-256 mismatch and a missing file produce the same user-facing message.

**Recommendation:** per USAGE.md §"Error Handling", switch on `AcervoError` at the SwiftAcervo boundary. Note `.offlineModeActive` is included — added in 0.8.1, surfaces when `ACERVO_OFFLINE=1` is set in the process environment.

```swift
} catch let error as AcervoError {
    switch error {
    case .modelNotFound(let id):
        throw VoxAltaError.modelNotAvailable("Model '\(id)' not found on CDN")
    case .integrityCheckFailed(let file, _, _):
        throw VoxAltaError.modelNotAvailable("File '\(file)' failed SHA-256 verification; re-download required")
    case .downloadSizeMismatch(let fileName, let expected, let actual):
        throw VoxAltaError.modelNotAvailable("File '\(fileName)' size mismatch (\(actual) vs \(expected))")
    case .componentNotRegistered(let id):
        throw VoxAltaError.modelNotAvailable("Unknown component '\(id)' (internal bug: forgot to register?)")
    case .componentNotHydrated(let id):  // new in v0.8.0
        throw VoxAltaError.modelNotAvailable("Component '\(id)' needs hydration before sync inspection")
    case .offlineModeActive:  // new in v0.8.1
        throw VoxAltaError.modelNotAvailable("ACERVO_OFFLINE=1 — refusing CDN fetch; model not present locally")
    case .fileNotInManifest(let fileName, let modelId):
        throw VoxAltaError.modelNotAvailable("Model '\(modelId)' does not include '\(fileName)' in its CDN manifest")
    case .manifestIntegrityFailed:
        throw VoxAltaError.modelNotAvailable("Manifest checksum mismatch; CDN copy may be corrupt")
    case .manifestDownloadFailed(let statusCode):
        throw VoxAltaError.modelNotAvailable("Manifest download failed (HTTP \(statusCode))")
    default:
        throw VoxAltaError.modelNotAvailable("SwiftAcervo error: \(error.localizedDescription)")
    }
}
```

Low priority — this is ergonomics, not correctness.

### Finding 4 — App Group entitlement is a downstream concern, but undocumented here — **Open**

**Context:** USAGE.md step 2 makes `group.intrusive-memory.models` a **required** capability for cross-app model sharing. Without it, each app falls back to `~/Library/Application Support/SwiftAcervo/SharedModels/` — non-shared, and the whole point of SwiftAcervo is defeated.

**Current state of SwiftVoxAlta:**
- No `.entitlements` file in this repo (there is no app target; the only executable is `diga`, which is an unsigned CLI tool).
- `diga` being unsigned means it **will** use the fallback path by design. That is fine.
- Downstream app consumers (Produciesta, any other app that pulls in SwiftVoxAlta) must enable the App Group themselves. There is no mention of this anywhere in `AGENTS.md` / `CLAUDE.md` / `README.md`.

**Recommendation:** add a short integration note to `AGENTS.md` ("Integrating into an app target") that lists the App Group requirement and points to SwiftAcervo's USAGE.md. No code change in this repo.

### Finding 5 — `Tokenizers` target collision (RESOLVED in this audit)

**Initial state (0.7.2 and 0.8.0 both):** `xcodebuild -resolvePackageDependencies` failed with:

```
multiple packages ('swift-tokenizers', 'swift-transformers') declare targets with a conflicting name: 'Tokenizers'; target names need to be unique across the package graph
```

**Root cause:** `intrusive-memory/SwiftTuberia` v0.4.0 depended on `huggingface/swift-transformers` (which ships a `Tokenizers` target). Everything else in the graph — `mlx-audio-swift`, `SwiftBruja` (via `swift-tokenizers-mlx`) — already uses `DePasqualeOrg/swift-tokenizers` with `traits: ["Swift"]`. The `Tokenizers` target appeared twice; SPM refused to resolve.

**Fix applied:** bumped `SwiftTuberia` from `^0.4.0` to `^0.5.0` in `Package.swift`. SwiftTuberia v0.5.0 migrated off `swift-transformers` onto `DePasqualeOrg/swift-tokenizers` (Swift trait) in commit `36887b9`, matching the stack SwiftBruja uses. Reference:

- `SwiftBruja/Package.swift:30-33` — `.package(url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx", .upToNextMajor(from: "0.2.0"), traits: ["Swift"])` with the comment *"Explicit Swift trait avoids pulling the Rust backend (binary xcframework)."*
- `mlx-audio-swift/Package.swift:39-40` — same pattern, Swift trait on both `swift-tokenizers-mlx` and `swift-tokenizers`.
- `SwiftTuberia/Package.swift` at v0.5.0 — same pattern.

**Graph delta after the bump:**

| Before (32 pins) | After (26 pins) |
|---|---|
| `swift-transformers` 1.3.0 | — removed — |
| `swift-huggingface` 0.9.0 | — removed — |
| `eventsource` 1.4.1 | — removed — |
| `swift-nio` 2.97.0 | — removed — |
| `swift-atomics` 1.3.0 | — removed — |
| `swift-system` 1.6.4 | — removed — |
| `swift-tokenizers` 0.3.2 (via swift-tokenizers-mlx) | ✅ kept, Swift backend only |
| `swift-tokenizers-mlx` 0.2.0 | ✅ kept |

**Rust backend status:** `DePasqualeOrg/swift-tokenizers` ships a `TokenizersRust` binary xcframework target behind the `Rust` trait (`Package.swift:69 — TokenizersRust-0.3.1.xcframework.zip`). No consumer in the SwiftVoxAlta graph sets that trait; every direct consumer (`swift-tokenizers-mlx`, `SwiftTuberia` v0.5.0, `mlx-audio-swift`, and `SwiftBruja` via `swift-tokenizers-mlx`) specifies `traits: ["Swift"]`, so the Rust binary artifact is never resolved or downloaded. This matches the Bruja convention.

**Verification:** `xcodebuild -resolvePackageDependencies -scheme SwiftVoxAlta` now succeeds; `Package.resolved` contains `swifttuberia 0.5.0`, `swift-tokenizers 0.3.2`, `swift-tokenizers-mlx 0.2.0`, and no `swift-transformers`.

---

## 4. Compliance matrix

| USAGE.md requirement | SwiftVoxAlta status |
|---|---|
| `Package.swift` depends on `SwiftAcervo >= 0.8.0` | ✅ pinned to `^0.8.2` (2026-04-26) |
| App Group `group.intrusive-memory.models` enabled on consuming targets | N/A in this repo (library + unsigned CLI); downstream apps must do this — see Finding 4 |
| Use `ensureModelsAvailable` / `ensureAvailable` / `ensureComponentReady` at startup | ✅ `ensureComponentReady` used in `loadModel` |
| Provide progress feedback via callback | ⚠️ No progress callback passed to `ensureComponentReady` — TTS downloads are silent from the user's POV. Minor; out of scope of this audit but worth noting |
| Handle `AcervoError` cases and convert to app-specific errors | ⚠️ Collapsed into one bucket — see Finding 3 |
| Call `Acervo.modelDirectory(for:)` / rely on `isModelAvailable` for loading | ✅ `TTSModelUtils` is the indirection layer; `isModelAvailable` used in `isModelInAcervo` |
| Test offline (already-present models load without network) | Not verified in this audit; logic allows it (cached `loadModel` returns without touching `ensureComponentReady` on subsequent calls with the same repo) |
| Prefer manifest-first APIs over hard-coded file lists | ⚠️ Currently declares file lists — see Finding 1 |
| Validate disk space first (`ModelDownloadManager.validateCanDownload`) | ❌ Not used. Memory headroom is checked; disk space is not |
| Serialize same-model downloads | ✅ `AcervoManager` is an actor; also `VoxAltaModelManager` itself is an actor |

---

## 5. Recommended next steps (if you want to adopt v0.8.0 fully)

1. **Migrate to bare descriptors** (Finding 1) — 15-line diff in `VoxAltaModelManager.swift`, 3 test assertions to update.
2. **Move `TTSModelUtils.loadModel` inside `withComponentAccess`** (Finding 2) — one-line move, validates the TOCTOU guard is actually doing work.
3. **Add `AcervoError` switch in the error-translation layer** (Finding 3) — roughly 15 lines.
4. **Add "App Group entitlement" note to `AGENTS.md`** (Finding 4) — docs only.
5. **(Optional) Add disk-space precheck** — `ModelDownloadManager.validateCanDownload(_:)` before `ensureComponentReady`. Deferred — not called out by the user.

Findings 1-3 are mechanical and non-breaking for callers. Finding 4 is pure docs. All four together would bring SwiftVoxAlta fully onto the v0.8.0 manifest-first idiom.
