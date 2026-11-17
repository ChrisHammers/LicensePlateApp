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

    func log(_ event: AnalyticsService.Event) {
        loggedEvents.append(event)
    }

    func setUserProperty(_ value: String?, forName name: String) {}

    func reset() {
        loggedEvents.removeAll()
    }
}
