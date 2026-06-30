//
//  GameplayLifecycleRules.swift
//  LicensePlateApp
//
//  Step 6.9.3 — Pure domain guardrails: trip vs game lifecycle (no SwiftData / Firebase).
//

import Foundation

/// Validation failures for lifecycle actions (trip container vs game instance).
enum GameplayLifecycleRulesError: Error, Equatable, Sendable, LocalizedError {
    /// Trips cannot be reset; only games can.
    case tripResetNotAllowed
    /// Game reset is not allowed when the trip session is no longer active (ended or cancelled).
    case gameResetTripTerminal
    /// Removing the last game instance would leave the trip with no games.
    case gameDeleteLastGameNotAllowed
    /// Another game of the same type is still live (`.created` or `.started`).
    case liveGameOfTypeAlreadyExists(definitionId: String)

    var errorDescription: String? {
        switch self {
        case .tripResetNotAllowed:
            return "Trips cannot be reset.".localized
        case .gameResetTripTerminal:
            return "Game reset is not available for this trip.".localized
        case .gameDeleteLastGameNotAllowed:
            return "A trip must keep at least one game.".localized
        case .liveGameOfTypeAlreadyExists(let definitionId):
            let displayName = GameType(rawValue: definitionId)?.displayName ?? definitionId
            return "End the current %@ game before starting another.".localized(displayName)
        }
    }
}

enum GameplayLifecycleRules {

    /// Trip-level reset is never valid (games reset individually).
    static func validateTripResetNeverAllowed() throws {
        throw GameplayLifecycleRulesError.tripResetNotAllowed
    }

    /// Game reset requires an active (non-terminal) trip session.
    static func validateGameResetAllowed(tripSessionState: TripSessionState) throws {
        if tripSessionState == .ended || tripSessionState == .cancelled {
            throw GameplayLifecycleRulesError.gameResetTripTerminal
        }
    }

    /// Deleting a game instance requires a non-terminal trip and at least two games (one must remain).
    static func validateGameDeleteAllowed(tripSessionState: TripSessionState, gameCountInSession: Int) throws {
        try validateGameResetAllowed(tripSessionState: tripSessionState)
        if gameCountInSession < 2 {
            throw GameplayLifecycleRulesError.gameDeleteLastGameNotAllowed
        }
    }

    /// A live round is configured or in progress (not ended/completed).
    static func isLiveRound(_ state: GameInstanceState) -> Bool {
        state == .created || state == .started
    }

    /// First live game of `definitionId`, optionally excluding one instance (e.g. the game being started).
    static func liveGame(
        ofType definitionId: String,
        in games: [GameInstance],
        excluding gameId: UUID? = nil
    ) -> GameInstance? {
        games.first { game in
            game.definitionId == definitionId
                && isLiveRound(game.commonConfig.lifecycleState)
                && game.id != gameId
        }
    }

    /// Adding a new instance requires no other live round of the same type on the trip.
    static func validateCanAddGame(ofType definitionId: String, existingGames: [GameInstance]) throws {
        if liveGame(ofType: definitionId, in: existingGames) != nil {
            throw GameplayLifecycleRulesError.liveGameOfTypeAlreadyExists(definitionId: definitionId)
        }
    }

    /// Starting a game requires no other live round of the same type besides this instance.
    static func validateCanStartGame(instance: GameInstance, existingGames: [GameInstance]) throws {
        if liveGame(ofType: instance.definitionId, in: existingGames, excluding: instance.id) != nil {
            throw GameplayLifecycleRulesError.liveGameOfTypeAlreadyExists(definitionId: instance.definitionId)
        }
    }
}
