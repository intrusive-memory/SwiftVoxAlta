//
//  EstimateModelMemoryTests.swift
//  SwiftVoxAlta
//
//  Sortie 3: Tests for `VoxAltaModelManager.estimateModelMemoryUsage()`.
//  Uses the `_setCurrentModelRepoForTesting` seam to avoid any disk/network
//  dependency — no model files are read or downloaded.
//

import Testing

@testable import SwiftVoxAlta

@Suite("VoxAltaModelManager — estimateModelMemoryUsage", .acervoEnvironment)
struct EstimateModelMemoryTests {
  @Test("Returns 0 when no repo is set")
  func zeroWhenNoRepo() async {
    let manager = VoxAltaModelManager()
    let mb = await manager.estimateModelMemoryUsage()
    #expect(mb == 0.0)
  }

  @Test("Returns 3400 for 1.7B repo string")
  func threeThousandFourHundredFor1_7B() async {
    let manager = VoxAltaModelManager()
    await manager._setCurrentModelRepoForTesting("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    let mb = await manager.estimateModelMemoryUsage()
    #expect(mb == 3400.0)
  }

  @Test("Returns 1200 for 0.6B repo string")
  func twelveHundredFor0_6B() async {
    let manager = VoxAltaModelManager()
    await manager._setCurrentModelRepoForTesting("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
    let mb = await manager.estimateModelMemoryUsage()
    #expect(mb == 1200.0)
  }

  @Test("Returns 0 for an unrecognized repo string")
  func zeroForUnknown() async {
    let manager = VoxAltaModelManager()
    await manager._setCurrentModelRepoForTesting("unknown")
    let mb = await manager.estimateModelMemoryUsage()
    #expect(mb == 0.0)
  }

  @Test("Returns 0 when repo is reset to nil")
  func zeroWhenResetToNil() async {
    let manager = VoxAltaModelManager()
    await manager._setCurrentModelRepoForTesting("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16")
    await manager._setCurrentModelRepoForTesting(nil)
    let mb = await manager.estimateModelMemoryUsage()
    #expect(mb == 0.0)
  }
}
