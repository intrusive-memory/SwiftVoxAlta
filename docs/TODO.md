# SwiftAcervo 0.16.x Migration

**Status:** ✅ Applied 2026-05-24. Package pin bumped to 0.16.0, `migrateIfNeeded()` removed, version-string doc drift fixed. `make build` + `make test-unit` (198 tests) both pass on the development branch.

Audit of SwiftVoxAlta against `/Users/stovak/Projects/SwiftAcervo/Docs/USAGE-library.md` (SwiftAcervo 0.16.1-dev).

**Overall assessment.** Code is largely 0.16-compatible — bare `ComponentDescriptor` registrations, `AcervoManager.shared.withComponentAccess`, `Acervo.ensureComponentReady`, `Acervo.isModelAvailable`, and a discriminated `AcervoError` switch are all already in idiomatic 0.16.x style. The one true API removal is `Acervo.migrateFromLegacyPaths()`, which no longer exists in 0.16.x. Everything else is doc drift (still saying "v0.10.0") and a routine pin bump.

---

## 1. Package.swift / Package.resolved bumps

### 1.1 Bump SwiftAcervo dependency ✅ 2026-05-24

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/Package.swift` (around line 83)
- **Current:**
  ```swift
  sibling(
    "SwiftAcervo",
    remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    from: "0.14.0"),
  ```
- **Required:**
  ```swift
  sibling(
    "SwiftAcervo",
    remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    from: "0.16.0"),
  ```
- After bumping, run a clean resolve so `Package.resolved` (currently pinned to revision `15fd376…`, `version 0.14.0` at lines 130–138) advances to the 0.16.x tag.

---

## 2. Code changes

### 2.1 `Acervo.migrateFromLegacyPaths()` no longer exists in 0.16.x ✅ 2026-05-24

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`
- **Lines:** 276–294 (`migrateIfNeeded()`), call site at line 456 (`_performLoad` → `migrateIfNeeded()`), and the gating `migrationAttempted` field at line 259.
- **Current behavior:** On first model load, calls `Acervo.migrateFromLegacyPaths()` and prints a "Migrated N model(s) to …" line to stderr.
- **Problem:** `migrateFromLegacyPaths` is not part of the 0.16.x public surface (not in `USAGE-library.md`, not in `Sources/SwiftAcervo/`). The build will fail.
- **Required change:** Delete `migrateIfNeeded()` entirely (the legacy `intrusive-memory/Models/{LLM,TTS,Audio,VLM}/` cache migration is an SwiftAcervo concern that 0.16.x dropped along with the legacy paths themselves). Remove the call at line 456 inside `_performLoad`, and the `migrationAttempted` field at line 259. Also strip the doc-comment fragments referencing "legacy cache migration" at lines 270–275, 455, and the `init` doc at line 263.
- Replacement: nothing. The App Group resolution already handles fresh installs correctly; there is no in-place legacy path to migrate from on 0.16.x consumers that have only ever used the App Group container.
- If the team needs to preserve a one-time migration story for users coming from a pre-App-Group SwiftAcervo cache, do it in a separate follow-up PR — do not block the 0.16 bump on it.

### 2.2 (Verify only — no change required) Bare `ComponentDescriptor` registrations

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`
- **Lines:** 127–181 (the `qwen3TTSComponentDescriptors` array — 7 descriptors).
- **Status:** Already uses the bare un-hydrated initializer `init(id:type:displayName:repoId:minimumMemoryBytes:metadata:)`. No `files:` arrays, no pre-baked `estimatedSizeBytes`. This is exactly the 0.16.x recommended pattern. Leave as-is.

### 2.3 (Verify only — no change required) `withComponentAccess` + `ensureComponentReady` flow

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift`
- **Lines:** 319–379 (`_loadModelWithComponentValidation`), 479 (`Acervo.ensureComponentReady(componentId)`).
- **Status:** Already uses `AcervoManager.shared.withComponentAccess(componentId) { @Sendable _ in ... }` and `Acervo.ensureComponentReady`. The `AcervoError` switch at 333–373 already discriminates `modelNotFound`, `integrityCheckFailed`, `downloadSizeMismatch`, `componentNotRegistered`, `componentNotHydrated`, `offlineModeActive`, `fileNotInManifest`, `manifestIntegrityFailed`, `manifestDownloadFailed`, with a `default` catch-all. All listed cases still exist in the 0.16.x `AcervoError` enum. Leave as-is.
- **Optional polish (low priority):** the `default:` branch could additionally match the new 0.16.x cases `manifestFetchFailed(slug:status:)`, `manifestModelIdMismatch(expected:actual:)`, `urlRequiredForSlug(_:)`, `componentFileNotFound(component:file:)`, `componentNotDownloaded(_:)`, `localPathNotFound(url:)`, etc. — but since none of those are reachable through the call sites VoxAlta actually invokes (`ensureComponentReady`, `withComponentAccess`), the default fall-through is acceptable.

### 2.4 (Verify only — no change required) `isModelAvailable` gating

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/Sources/SwiftVoxAlta/VoxAltaModelManager.swift:300–302`
- **Status:** The synchronous probe `Acervo.isModelAvailable(modelId)` is used from a `nonisolated` helper exposed as `isModelInAcervo`. This is the correct fast-path API in 0.16.x (the doc explicitly says: "Prefer `availability(_:)` for UI; use this in fast-path guards inside `ensureAvailable` flows"). Since VoxAlta is a library — not a UI consumer — the synchronous form is fine.
- **Optional polish (low priority):** if a downstream UI consumer (Produciesta) wants three-state progress, expose an additional async helper `availability(_:) async -> ModelAvailability` forwarding to `AcervoManager.shared.availability(_:)`. Not required for the 0.16 bump.

### 2.5 (Verify only — no change required) `Acervo.slugify` + `Acervo.component`

- **Files:** `VoxAltaModelManager.swift:116` (`Acervo.slugify(rawValue)`), `VoxAltaModelManager.swift:474` (`Acervo.component(componentId)`), `DigaBinaryIntegrationTests.swift:139` (`Acervo.sharedModelsDirectory.path`).
- **Status:** All three APIs exist verbatim in 0.16.x. Leave as-is.

---

## 3. Documentation updates

All four foundational docs still say "SwiftAcervo v0.10.0" even though the pin is v0.14 and we are bumping to v0.16. None of the behavioural claims have changed (resolution order, no-silent-fallback, fatalError trap), only the version string.

### 3.1 README — version string drift ✅ 2026-05-24

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/README.md:133`
- **Current:** `… SwiftAcervo v0.10.0 resolves its App Group ID in this order…`
- **Required:** drop the version pin from the sentence (it ages out of date every cycle). Replace with: `… SwiftAcervo resolves its App Group ID in this order…`

### 3.2 AGENTS — two version-string occurrences ✅ 2026-05-24

- **File:** `/Users/stovak/Projects/SwiftVoxAlta/AGENTS.md`
- **Line 48:** same fix as README (drop "v0.10.0").
- **Line 682:** same fix.
- Also add a Changelog entry under the existing `## Changelog` block (around lines 757+) noting the 0.14 → 0.16 bump and the removal of the `migrateFromLegacyPaths` call site.

### 3.3 CLAUDE.md and GEMINI.md

- **Files:** `/Users/stovak/Projects/SwiftVoxAlta/CLAUDE.md:64` and `/Users/stovak/Projects/SwiftVoxAlta/GEMINI.md:44`.
- Both already point at AGENTS.md's "App Group configuration (required)" section by reference. No version string to fix. Leave as-is.

### 3.4 (Optional) USAGE-library.md cross-link

- In AGENTS.md's App Group section (around line 680), link to `Docs/USAGE-library.md` in the SwiftAcervo repo so readers can confirm the resolution order in the canonical source rather than the copy embedded in AGENTS.md.

---

## 4. CI / Makefile / entitlements

### 4.1 (No change required) GitHub Actions workflows

- `/Users/stovak/Projects/SwiftVoxAlta/.github/workflows/tests.yml:8`
- `/Users/stovak/Projects/SwiftVoxAlta/.github/workflows/release.yml:19`
- `/Users/stovak/Projects/SwiftVoxAlta/.github/workflows/ensure-model-cdn.yml:20`
- All three already export `ACERVO_APP_GROUP_ID: group.intrusive-memory.models` at job level. The historical v0.10 audit finding ("no `ACERVO_APP_GROUP_ID` exports in CI workflows") is no longer accurate. Leave as-is.

### 4.2 (No change required) Makefile

- `/Users/stovak/Projects/SwiftVoxAlta/Makefile:123–128` already defers to `Acervo.sharedModelsDirectory` for the model cache destination instead of hardcoding a path. Leave as-is.

### 4.3 (No change required) Entitlements

- SwiftVoxAlta is a library + the unsigned `diga` CLI; neither owns an `.entitlements` file. The App Group entitlement is delivered by downstream UI apps (Produciesta) and is already documented in AGENTS.md §680. Leave as-is.

---

## 5. Tests

### 5.1 (No change required) `AcervoEnvironmentTrait`

- `/Users/stovak/Projects/SwiftVoxAlta/Tests/SwiftVoxAltaTests/AcervoEnvironmentTrait.swift`
- `/Users/stovak/Projects/SwiftVoxAlta/Tests/DigaTests/AcervoEnvironmentTrait.swift`
- Both correctly `setenv("ACERVO_APP_GROUP_ID", "group.intrusive-memory.models", 0)` before any Acervo path resolution. Pattern still matches the 0.16.x resolution order. Leave as-is.

### 5.2 (No change required) `ComponentDescriptorRegistrationTests`

- `/Users/stovak/Projects/SwiftVoxAlta/Tests/SwiftVoxAltaTests/ComponentDescriptorRegistrationTests.swift`
- Asserts `descriptor.needsHydration == true` and `descriptor.files.isEmpty` after registration — exactly the 0.16.x bare-descriptor invariant. Leave as-is.

### 5.3 Strip `migrateIfNeeded`-related test side-effects (only if §2.1 changes any test fixture)

- If §2.1's deletion of `migrateIfNeeded()` removes a public symbol or stderr line that a test asserts on, drop those expectations. A grep of `Tests/` shows no test currently calls `migrateIfNeeded` or asserts on the "Migrated N model(s)" stderr line, so this is almost certainly a no-op — verify after applying §2.1.

---

## Summary

- **One real code change:** delete `migrateIfNeeded()` and its call site (§2.1).
- **One pin bump:** Package.swift `0.14.0` → `0.16.0` (§1.1).
- **Three doc edits:** strip stale "v0.10.0" version strings in README and AGENTS (§3.1, §3.2).
- Everything else flagged in the historical v0.10 audit (component registrations, error mapping, CI env var, Makefile path hardcoding, App Group docs) is already compliant with 0.16.x. No further work required.
