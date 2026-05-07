//
//  PreflightLeakProbeTests.swift
//  SwiftVoxAlta
//
//  Sortie 1: Preflight Leak Probe — empirical RSS measurement of 3
//  loadModel / unloadModel cycles. Skipped by default; run via:
//
//    make test-leak-probe
//
//  (or manually:)
//    VOXALTA_RUN_LEAK_PROBE=1 xcodebuild test \
//      -scheme SwiftVoxAlta-Package \
//      -destination 'platform=macOS,arch=arm64' \
//      -only-testing:SwiftVoxAltaTests/PreflightLeakProbeTests/testLoadUnloadCycleLeakProbe
//

import Foundation
import Testing
import Darwin
@testable import SwiftVoxAlta

@Suite("Preflight Leak Probe", .acervoEnvironment)
struct PreflightLeakProbeTests {

    @Test("3-cycle load/unload RSS probe (gated by VOXALTA_RUN_LEAK_PROBE=1)")
    func testLoadUnloadCycleLeakProbe() async throws {
        // Skip unless explicitly activated. Checks two mechanisms because
        // xcodebuild 26+ does not propagate the parent shell's environment to
        // the xctest runner process.
        //
        // Mechanism 1: env var (works when running the test binary directly)
        // Mechanism 2: sentinel file (works via xcodebuild, created by
        //   `make test-leak-probe` before running and cleaned up after)
        let envEnabled = ProcessInfo.processInfo.environment["VOXALTA_RUN_LEAK_PROBE"] == "1"
        let fileEnabled = FileManager.default.fileExists(atPath: "/tmp/voxalta_run_leak_probe")
        guard envEnabled || fileEnabled else {
            return  // Skipped; gate it deliberately to avoid running on every test pass.
        }

        // ── 1. Baseline RSS ──────────────────────────────────────────────────
        let manager = VoxAltaModelManager()
        let rssBefore = currentRSSMB()

        // ── 2. Three load/unload cycles ──────────────────────────────────────
        // Use _loadModelDiscardingResult to avoid transferring a non-Sendable
        // SpeechGenerationModel result across the actor isolation boundary.
        var afterLoadRSS: [Double] = []
        var afterUnloadRSS: [Double] = []

        for _ in 0..<3 {
            try await manager._loadModelDiscardingResult(repo: Qwen3TTSModelRepo.base1_7B.rawValue)
            afterLoadRSS.append(currentRSSMB())
            await manager.unloadModel()
            // 2s drain: lets MLX async deallocation and autorelease pools flush.
            try await Task.sleep(nanoseconds: 2_000_000_000)
            afterUnloadRSS.append(currentRSSMB())
        }

        // ── 3. Compute per-cycle marginal deltas ─────────────────────────────
        let d1 = afterUnloadRSS[0] - rssBefore
        let d2 = afterUnloadRSS[1] - afterUnloadRSS[0]
        let d3 = afterUnloadRSS[2] - afterUnloadRSS[1]
        let cumulative = afterUnloadRSS[2] - rssBefore
        let marginalAvg = (d2 + d3) / 2.0

        // ── 4. Determine verdict (3-cycle marginal-average thresholds) ────────
        // d1 includes one-time MLX/Metal framework setup costs.
        // d2 and d3 isolate pure per-cycle retention — this is the diagnostic.
        let verdict: String
        if marginalAvg > 250.0 {
            verdict = "LEAK SUSPECTED"
        } else if marginalAvg < 50.0 {
            verdict = "NO LEAK"
        } else {
            verdict = "INCONCLUSIVE"
        }

        // ── 5. Build the report ──────────────────────────────────────────────
        let now = ISO8601DateFormatter().string(from: Date())

        let report = """
        # Preflight Leak Probe Result

        Date: \(now)
        Model: mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16
        Cycles: 3
        Drain per cycle: 2s

        ## RSS measurements (MB)
        Before load:                \(String(format: "%.2f", rssBefore))
        After load (cycle 1):       \(String(format: "%.2f", afterLoadRSS[0]))
        After unload (cycle 1):     \(String(format: "%.2f", afterUnloadRSS[0]))
        After load (cycle 2):       \(String(format: "%.2f", afterLoadRSS[1]))
        After unload (cycle 2):     \(String(format: "%.2f", afterUnloadRSS[1]))
        After load (cycle 3):       \(String(format: "%.2f", afterLoadRSS[2]))
        After unload (cycle 3):     \(String(format: "%.2f", afterUnloadRSS[2]))

        ## Per-cycle marginal deltas (MB)
        d1 (cycle 1, includes one-time overhead):  \(String(format: "%.2f", d1))
        d2 (cycle 2 marginal):                     \(String(format: "%.2f", d2))
        d3 (cycle 3 marginal):                     \(String(format: "%.2f", d3))
        Marginal average (d2+d3)/2:                \(String(format: "%.2f", marginalAvg))
        Cumulative (3 cycles):                     \(String(format: "%.2f", cumulative))

        ## Thresholds (3-cycle, marginal-average based)
        LEAK SUSPECTED if marginalAvg > 250.0
        NO LEAK         if marginalAvg < 50.0
        INCONCLUSIVE    otherwise

        Verdict: \(verdict)

        ## Interpretation guide
        - d1 includes one-time MLX/Metal framework setup costs that occur on first model load.
        - d2 and d3 measure pure per-cycle retention. If they are near zero, the residual is structural.
        - If d2 ≈ d3 ≈ d1 (~340 MB), this is a linear leak — confirmed mission premise.
        - The unloadFreed magnitude (typically ~8.4 GB on this model) is NOT in the verdict — only marginal residue is.

        ## Notes
        - RSS via mach_task_basic_info.resident_size; approximate, includes shared memory.
        - 2s drain after each unload, before measuring the cycle's afterUnload RSS.
        - Probe runs inside xctest, not Produciesta. Deltas are comparable; absolutes are not.
        - Invocation: xcodebuild test via make test-leak-probe (Swift Testing, .acervoEnvironment trait handles ACERVO_APP_GROUP_ID bootstrap).
        """

        // ── 6. Write LEAK_PROBE_RESULT.md ────────────────────────────────────
        // File lives at Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift
        // Four deletingLastPathComponent() calls walk up to the project root.
        let fileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = fileURL
            .deletingLastPathComponent()  // Preflight/
            .deletingLastPathComponent()  // SwiftVoxAltaTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root

        let reportURL = projectRoot.appendingPathComponent("LEAK_PROBE_RESULT.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        // ── 7. Mirror to stderr ──────────────────────────────────────────────
        let stderrData = Data(("\n--- LEAK PROBE RESULT ---\n" + report + "\n--- END LEAK PROBE RESULT ---\n").utf8)
        FileHandle.standardError.write(stderrData)
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
