import DigaCLICore

// `DigaCommand` is an `AsyncParsableCommand`, so its entry point is async. The
// command logic itself lives in the `DigaCLICore` library so the same entry
// point can be embedded in an Xcode tool target (see TODO-cli-bundling.md).
//
// `runAsMain()` is used rather than a bare `await DigaCommand.main()` because
// the async `main()` overload is `@available`-gated and top-level `main.swift`
// code is not an availability-annotated scope — a bare call would resolve to
// the synchronous overload and abort at runtime. `runAsMain()` wraps the call
// in an annotated context so the async overload is selected.
await DigaCommand.runAsMain()
