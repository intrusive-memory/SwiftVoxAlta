//
//  ProcessMemory.swift
//  SwiftVoxAlta
//
//  Note: This function duplicates the inline `currentRSSMB()` helper from
//  `Tests/SwiftVoxAltaTests/Preflight/PreflightLeakProbeTests.swift`.
//  The duplication is intentional — Sortie 1 (the preflight probe) must run
//  before the Telemetry/ folder exists, so the probe cannot depend on this file.
//

import Darwin
import Foundation

/// Returns the current process's resident set size (RSS) in megabytes.
///
/// Uses `task_info` with `MACH_TASK_BASIC_INFO`. Returns 0.0 on failure;
/// telemetry must never block or throw on the caller. The value is approximate
/// and includes shared memory and macOS-compressed pages — useful for **deltas**,
/// not absolutes.
public func getCurrentProcessMemory() -> Double {
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
