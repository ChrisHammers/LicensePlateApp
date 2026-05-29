//
//  GameInstanceLifecycleRuleTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.3 — Pure rules for game instance lifecycle actions vs trip state.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameInstanceLifecycleRuleTests {

    @Test func validateGameResetAllowedWhenTripActive() throws {
        try GameplayLifecycleRules.validateGameResetAllowed(tripSessionState: .active)
    }

    @Test func validateGameResetAllowedWhenTripCreated() throws {
        try GameplayLifecycleRules.validateGameResetAllowed(tripSessionState: .created)
    }

    @Test func validateGameResetThrowsWhenTripEnded() throws {
        do {
            try GameplayLifecycleRules.validateGameResetAllowed(tripSessionState: .ended)
            Issue.record("Expected gameResetTripTerminal")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameResetTripTerminal)
            #expect(error != .tripResetNotAllowed)
        }
    }

    @Test func validateGameResetThrowsWhenTripCancelled() throws {
        do {
             try GameplayLifecycleRules.validateGameResetAllowed(tripSessionState: .cancelled)
            Issue.record("Expected gameResetTripTerminal")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameResetTripTerminal)
            #expect(error != .tripResetNotAllowed)
        }
    }

    @Test func validateGameDeleteAllowedWhenTwoGamesAndTripActive() throws {
        try GameplayLifecycleRules.validateGameDeleteAllowed(tripSessionState: .active, gameCountInSession: 2)
        try GameplayLifecycleRules.validateGameDeleteAllowed(tripSessionState: .created, gameCountInSession: 3)
    }

    @Test func validateGameDeleteThrowsWhenOnlyOneGame() throws {
        do {
            try GameplayLifecycleRules.validateGameDeleteAllowed(tripSessionState: .active, gameCountInSession: 1)
            Issue.record("Expected gameDeleteLastGameNotAllowed")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameDeleteLastGameNotAllowed)
        }
    }

    @Test func validateGameDeleteThrowsWhenTripEnded() throws {
        do {
            try GameplayLifecycleRules.validateGameDeleteAllowed(tripSessionState: .ended, gameCountInSession: 2)
            Issue.record("Expected gameResetTripTerminal")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameResetTripTerminal)
        }
    }
}
