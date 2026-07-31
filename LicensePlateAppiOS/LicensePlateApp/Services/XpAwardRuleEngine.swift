//
//  XpAwardRuleEngine.swift
//  LicensePlateApp
//
//  Maps canonical discovery resolution to XP, trip scoring, and personal-history axes (MVP).
//

import Foundation

/// Computed awards for the three axes (MVP: often mirrors `finalOutcome`).
struct XpAwardComputation: Sendable, Equatable {
    var tripScoringNet: Int
    var personalHistoryNet: Int
    var xpNet: Int
    var xpReason: XpReasonCode
}

enum XpAwardRuleEngine {

    /// Derives MVP net awards from a persisted `DiscoveryResolution` and game mode (for reason code selection).
    /// - Parameter tripMode: When `.solo` and outcome is first accepted discovery, XP reason uses `soloNewDiscovery`.
    static func compute(
        from resolution: DiscoveryResolution,
        gameMode: GameMode,
        tripMode: TripMode? = nil,
        rewards: ProgressionRewardsConfig = ProgressionRewardsConfigProvider.shared.current
    ) -> XpAwardComputation {
        let xp = xpNetAndReason(
            finalOutcome: resolution.finalOutcome,
            gameMode: gameMode,
            tripMode: tripMode,
            rewards: rewards
        )
        return XpAwardComputation(
            tripScoringNet: xp.amount,
            personalHistoryNet: xp.amount,
            xpNet: xp.amount,
            xpReason: xp.reason
        )
    }

    private static func xpNetAndReason(
        finalOutcome: DiscoveryResolutionOutcome,
        gameMode: GameMode,
        tripMode: TripMode?,
        rewards: ProgressionRewardsConfig
    ) -> (amount: Int, reason: XpReasonCode) {
        let baseDiscovery = rewards.xp.baseDiscoveryXp
        switch finalOutcome {
        case .pending:
            return (0, .discoveryClaimPendingResolution)
        case .acceptedFirst:
            if tripMode == .solo {
                return (baseDiscovery, .soloNewDiscovery)
            }
            var reason: XpReasonCode = switch gameMode {
            case .competitive: .competitiveFirstFinder
            case .collaborative: .collaborativeSharedFinder
            }
            if reason == .competitiveFirstFinder {
                return (rewards.xp.baseDiscoveryXp + rewards.xp.firstFinderBonusXp, reason)
            }
            
            return (baseDiscovery, reason)
        case .acceptedLate:
            // Late competitive find keeps base discovery XP; first-finder bonus is not awarded.
            return (baseDiscovery, .competitiveLateFinder)
        case .acceptedShared:
            return (baseDiscovery, .collaborativeSharedFinder)
        case .rejectedDuplicate:
            return (0, .duplicateNoXp)
        case .rejectedPersonalDuplicate:
            return (0, .personalRefindNoXp)
        case .rejectedRisk:
            return (0, .riskRejectedNoXp)
        case .rejectedInvalidState:
            return (0, .duplicateNoXp)
        }
    }
}
