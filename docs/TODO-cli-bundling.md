# TODO — Extract `DigaCLICore` library (CLI-bundling prep)

Part of a cross-repo effort to embed the `diga` CLI (and siblings) into `Produciesta.app`,
signed with the `group.intrusive-memory.models` App Group, following the SwiftVinetas pattern
(`VinetasCLICore` library + thin executable). An Xcode tool target cannot link an SPM
*executable* product, so the command logic must live in a **library** product.

Reference: `/Users/stovak/Projects/SwiftVinetas/Package.swift` and
`/Users/stovak/Projects/Vinetas/VinetasCLI/VinetasCLIMain.swift`.

## Goal
Expose a new `DigaCLICore` library product holding the `diga` command, reduce the `diga`
executable to a thin entry point, keep build and tests green.

## Note on shape
Unlike Vinetas/Echada (router roots composing subcommands), `DigaCommand` is a **single
command** with its own flags and `run()` — no subcommands. So the root struct itself moves
into the library, and the executable enters it via `main.swift` + top-level `await`.

## Steps
1. **Package.swift**
   - Add product: `.library(name: "DigaCLICore", targets: ["DigaCLICore"])`.
   - Add target `DigaCLICore` whose deps = the current `diga` exec target deps
     (`SwiftVoxAlta`, `ArgumentParser`, `SwiftAcervo`), `swiftSettings:
     [.enableUpcomingFeature("StrictConcurrency")]`. (Drop the `path:` override if the dir
     name now matches the target name.)
   - Slim `diga` exec target deps to `["DigaCLICore", ArgumentParser]`; keep
     `path: "Sources/diga"` and swiftSettings.
   - In the `DigaTests` target deps, replace `"diga"` → `"DigaCLICore"`.

2. **Move sources** all of `Sources/diga/` → `Sources/DigaCLICore/`:
   `DigaCommand.swift`, `DigaEngine.swift`, `AudioFileWriter.swift`, `AudioPlayback.swift`,
   `BuiltinVoices.swift`, `VoiceStore.swift`, `Version.swift`.
   - In `DigaCommand.swift`: **remove `@main`**; make `public struct DigaCommand`,
     `public init() {}`, `public static let configuration`, `public mutating func run() async
     throws`, and `public` on its parsed (`@Flag`/`@Option`/`@Argument`) properties.
   - Helpers (`DigaEngine`, `VoiceStore`, `BuiltinVoices`, `AudioFileWriter`, `AudioPlayback`,
     `DigaVersion`, error enums) stay `internal` — tests reach them via `@testable`.

3. **Thin executable** — create `Sources/diga/main.swift` (this is the one package that
   legitimately uses `main.swift`):
   ```swift
   import DigaCLICore
   await DigaCommand.main()   // AsyncParsableCommand.main() is async
   ```
   Delete the old `DigaCommand.swift` from `Sources/diga/`.

4. **Tests** — change `@testable import diga` → `@testable import DigaCLICore` in:
   `DigaCLIIntegrationTests`, `DigaAudioPlaybackTests`, `DigaVoiceStoreTests`,
   `DigaVoxIntegrationTests`, `DigaEngineTests`, `DigaAudioFileWriterTests`.
   `DigaBinaryIntegrationTests` (runs the built `./bin/diga` subprocess) is **untouched**.
   `DigaVersionTests` / `DigaReleaseTests` are untouched.

5. **Build green** via Makefile / xcodebuild (NEVER `swift build`/`swift test`):
   `make resolve && make install && make test` (destination `platform=macOS,arch=arm64`).

6. **Version**: bump `DigaVersion.current` (in the moved `Version.swift`) to `0.12.0`
   (or `-dev` per repo convention).

## Wrap-up
- Branch off `development`, commit, push to `development`, then run `/create-pull-request`.
- **Do NOT tag/release in this PR.** Release to **0.12.0** happens after merge (via
  `/ship-swift-library`, minor bump). Produciesta pins this remotely and needs the release.

## Guardrails
- No source here uses `Bundle.module` — the new target needs no `resources:`.
- Confirm the `diga` exec target compiles with a `main.swift` containing top-level `await`
  under the repo's swift-tools / language mode. The root must NOT keep `@main` once it lives
  in the library (would double-define the entry point).
