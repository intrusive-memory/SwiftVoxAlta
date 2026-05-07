//
//  ProcessMemoryTests.swift
//  SwiftVoxAlta
//
//  Sortie 3: Tests for the `getCurrentProcessMemory()` helper.
//

import Testing

@testable import SwiftVoxAlta

@Suite("ProcessMemory — getCurrentProcessMemory", .acervoEnvironment)
struct ProcessMemoryTests {
  @Test("Returns a positive RSS value on a live process")
  func returnsPositive() {
    #expect(getCurrentProcessMemory() > 0.0)
  }

  @Test("Increases (or stays equal) after allocating 50 MB and holding a strong reference")
  func increasesAfterAllocation() {
    let before = getCurrentProcessMemory()
    let buffer = Array(repeating: UInt8(0), count: 50 * 1024 * 1024)  // 50 MB
    let after = getCurrentProcessMemory()
    #expect(after >= before)
    // Keep buffer alive past the second sample so compressed-memory doesn't reclaim it before measurement.
    _ = buffer.count
  }
}
