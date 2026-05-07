//
//  MockTelemetryReporter.swift
//  SwiftVoxAltaTests
//
//  Test-only reporter that records every captured event in order.
//

import Foundation

@testable import SwiftVoxAlta

actor MockTelemetryReporter: VoxAltaTelemetryReporter {
  private var capturedEvents: [VoxAltaTelemetryEvent] = []

  func capture(_ event: VoxAltaTelemetryEvent) async {
    capturedEvents.append(event)
  }

  var events: [VoxAltaTelemetryEvent] {
    capturedEvents
  }
}
