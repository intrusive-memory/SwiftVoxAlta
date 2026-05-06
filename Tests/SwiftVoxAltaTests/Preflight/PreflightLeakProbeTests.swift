//
//  PreflightLeakProbeTests.swift
//  SwiftVoxAlta
//
//  Sortie 1: Preflight Leak Probe — empirical RSS measurement of a single
//  loadModel / unloadModel cycle. Skipped by default; run via:
//
//    VOXALTA_RUN_LEAK_PROBE=1 xcodebuild test \
//      -scheme SwiftVoxAlta-Package \
//      -destination 'platform=macOS,arch=arm64' \
//      -only-testing:SwiftVoxAltaTests/PreflightLeakProbeTests/testLoadUnloadCycleLeakProbe
//

import XCTest
import Darwin
@testable import SwiftVoxAlta

final class PreflightLeakProbeTests: XCTestCase {

    func testLoadUnloadCycleLeakProbe() async throws {
        // Skip unless explicitly activated. Checks two mechanisms because
        // xcodebuild 26+ does not propagate the parent shell's environment to
        // the xctest runner process (documented in AcervoEnvironmentTrait.swift).
        //
        // Mechanism 1: env var (works when running the test binary directly)
        // Mechanism 2: sentinel file (works via xcodebuild, created before
        //   running and deleted after: `touch /tmp/voxalta_run_leak_probe`)
        let envEnabled = ProcessInfo.processInfo.environment["VOXALTA_RUN_LEAK_PROBE"] == "1"
        let fileEnabled = FileManager.default.fileExists(atPath: "/tmp/voxalta_run_leak_probe")
        try XCTSkipIf(
            !envEnabled && !fileEnabled,
            "Set VOXALTA_RUN_LEAK_PROBE=1 or `touch /tmp/voxalta_run_leak_probe` to run the preflight leak probe."
        )

        // Bootstrap ACERVO_APP_GROUP_ID if not already set in the test runner
        // process. xcodebuild 26+ strips the parent environment, so Acervo's
        // fatalError guard would otherwise crash the test runner on first access.
        if ProcessInfo.processInfo.environment["ACERVO_APP_GROUP_ID"] == nil {
            setenv("ACERVO_APP_GROUP_ID", "group.intrusive-memory.models", 0)
        }

        // ── 1. Baseline RSS ──────────────────────────────────────────────────
        let rssBeforeMB = currentRSSMB()

        // ── 2. Load model ────────────────────────────────────────────────────
        // Use _loadModelDiscardingResult to avoid transferring a non-Sendable
        // SpeechGenerationModel result across the actor isolation boundary.
        let manager = VoxAltaModelManager()
        try await manager._loadModelDiscardingResult(repo: Qwen3TTSModelRepo.base1_7B.rawValue)
        let rssAfterLoadMB = currentRSSMB()

        // ── 3. Unload model ──────────────────────────────────────────────────
        await manager.unloadModel()

        // 2s drain: lets MLX async deallocation and autorelease pools flush.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let rssAfterUnloadMB = currentRSSMB()

        // ── 4. Compute deltas ────────────────────────────────────────────────
        let loadGrew     = rssAfterLoadMB   - rssBeforeMB
        let unloadFreed  = rssAfterLoadMB   - rssAfterUnloadMB
        let netDelta     = rssAfterUnloadMB - rssBeforeMB

        // ── 5. Determine verdict ─────────────────────────────────────────────
        let verdict: String
        if netDelta > 1000.0 {
            verdict = "LEAK SUSPECTED"
        } else if netDelta < 200.0 {
            verdict = "NO LEAK"
        } else {
            verdict = "INCONCLUSIVE"
        }

        // ── 6. Build the report ──────────────────────────────────────────────
        let now = ISO8601DateFormatter().string(from: Date())

        let report = """
        # Preflight Leak Probe Result

        Date: \(now)
        Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
        Cycles: 1

        ## RSS measurements (MB)
        Before load:        \(String(format: "%.2f", rssBeforeMB))
        After load:         \(String(format: "%.2f", rssAfterLoadMB))
        After unloadModel:  \(String(format: "%.2f", rssAfterUnloadMB))

        ## Deltas (MB)
        loadGrew:           \(String(format: "%.2f", loadGrew))
        unloadFreed:        \(String(format: "%.2f", unloadFreed))
        netDelta:           \(String(format: "%.2f", netDelta))

        ## Thresholds
        LEAK SUSPECTED if netDelta > 1000.0
        NO LEAK         if netDelta < 200.0
        INCONCLUSIVE    otherwise

        Verdict: \(verdict)

        ## Notes
        - RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
        - 2s drain window between unloadModel() and final RSS sample.
        - This probe runs inside xctest, not Produciesta. Absolute RSS values are not directly comparable across processes; deltas are.
        """

        // ── 7. Write LEAK_PROBE_RESULT.md ────────────────────────────────────
        // File lives at Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift
        // Three deletingLastPathComponent() calls walk up to the project root.
        let fileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = fileURL
            .deletingLastPathComponent()  // Preflight/
            .deletingLastPathComponent()  // SwiftVoxAltaTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root

        let reportURL = projectRoot.appendingPathComponent("LEAK_PROBE_RESULT.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        // ── 8. Mirror to stderr ──────────────────────────────────────────────
        let stderrData = Data(("\n--- LEAK PROBE RESULT ---\n" + report + "\n--- END LEAK PROBE RESULT ---\n").utf8)
        FileHandle.standardError.write(stderrData)

        // ── 9. Always pass — verdict is data, not a gate ─────────────────────
        XCTAssertTrue(true)
    }

    // MARK: - Private RSS Helper

    /// Returns the current process RSS in megabytes via mach_task_basic_info.
    ///
    /// The value is approximate and includes shared memory. Use deltas, not absolutes.
    private func currentRSSMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
}
