//
//  MockAnalyticsService.swift
//  LicensePlateAppTests
//
//  Step 13 — Spy for AnalyticsLogging. Records events for assertions; no singletons.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockAnalyticsService: AnalyticsLogging {
    var loggedEvents: [AnalyticsService.Event] = []
    var loggedNames: [(name: String, parameters: [String: Any])] = []
    var screenViewName: String?

    func log(_ event: AnalyticsService.Event) {
        loggedEvents.append(event)
    }

    func log(_ name: String, parameters: [String: Any]) {
        loggedNames.append((name, parameters))
        if name == "screen_view", let screen = parameters["screen_name"] as? String {
            screenViewName = screen
        }
    }

    func reset() {
        loggedEvents.removeAll()
        loggedNames.removeAll()
        screenViewName = nil
    }
}
