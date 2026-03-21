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

    var errorDescription: String? {
        switch self {
        case .tripResetNotAllowed:
            return "Trips cannot be reset.".localized
        case .gameResetTripTerminal:
            return "Game reset is not available for this trip.".localized
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
}
