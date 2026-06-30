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

    // MARK: - Live round per game type

    @Test func isLiveRoundIsTrueForCreatedAndStarted() {
        #expect(GameplayLifecycleRules.isLiveRound(.created) == true)
        #expect(GameplayLifecycleRules.isLiveRound(.started) == true)
        #expect(GameplayLifecycleRules.isLiveRound(.ended) == false)
        #expect(GameplayLifecycleRules.isLiveRound(.completed) == false)
    }

    @Test func validateCanAddGameThrowsWhenLiveGameOfSameTypeExists() throws {
        let sessionId = UUID()
        let live = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .started)
        )
        do {
            try GameplayLifecycleRules.validateCanAddGame(
                ofType: GameType.licensePlate.rawValue,
                existingGames: [live]
            )
            Issue.record("Expected liveGameOfTypeAlreadyExists")
        } catch let error as GameplayLifecycleRulesError {
            if case .liveGameOfTypeAlreadyExists(let definitionId) = error {
                #expect(definitionId == GameType.licensePlate.rawValue)
            } else {
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test func validateCanAddGameThrowsWhenCreatedGameOfSameTypeExists() throws {
        let sessionId = UUID()
        let live = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        )
        do {
            try GameplayLifecycleRules.validateCanAddGame(
                ofType: GameType.licensePlate.rawValue,
                existingGames: [live]
            )
            Issue.record("Expected liveGameOfTypeAlreadyExists")
        } catch let error as GameplayLifecycleRulesError {
            if case .liveGameOfTypeAlreadyExists = error {} else {
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test func validateCanAddGameAllowsWhenPriorRoundEnded() throws {
        let sessionId = UUID()
        let ended = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .ended)
        )
        try GameplayLifecycleRules.validateCanAddGame(
            ofType: GameType.licensePlate.rawValue,
            existingGames: [ended]
        )
    }

    @Test func validateCanAddGameAllowsDifferentGameType() throws {
        let sessionId = UUID()
        let lp = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .started)
        )
        try GameplayLifecycleRules.validateCanAddGame(
            ofType: GameType.roadSignBingo.rawValue,
            existingGames: [lp]
        )
    }

    @Test func validateCanStartGameThrowsWhenAnotherSameTypeIsLive() throws {
        let sessionId = UUID()
        var first = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        )
        first.id = UUID()
        var second = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        )
        second.id = UUID()
        do {
            try GameplayLifecycleRules.validateCanStartGame(instance: second, existingGames: [first, second])
            Issue.record("Expected liveGameOfTypeAlreadyExists")
        } catch let error as GameplayLifecycleRulesError {
            if case .liveGameOfTypeAlreadyExists = error {} else {
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    @Test func validateCanStartGameAllowsWhenOnlySelfIsLive() throws {
        let sessionId = UUID()
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        )
        game.id = UUID()
        try GameplayLifecycleRules.validateCanStartGame(instance: game, existingGames: [game])
    }
}
