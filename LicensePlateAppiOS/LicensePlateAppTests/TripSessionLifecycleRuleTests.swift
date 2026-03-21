//
//  TripSessionLifecycleRuleTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.3 — Pure rules for trip container lifecycle.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSessionLifecycleRuleTests {

    @Test func validateTripResetNeverAllowedThrows() throws {
        do {
            try GameplayLifecycleRules.validateTripResetNeverAllowed()
            Issue.record("Expected GameplayLifecycleRulesError.tripResetNotAllowed")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .tripResetNotAllowed)
            #expect(error != .gameResetTripTerminal)
        }
    }
}
