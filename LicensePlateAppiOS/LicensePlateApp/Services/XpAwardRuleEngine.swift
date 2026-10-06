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
            // Local ledger settles base discovery only. First-finder / unique / first-of-day
            // are separate cloud component grants (and separate toast lines).
            if tripMode == .solo {
                return (baseDiscovery, .soloNewDiscovery)
            }
            switch gameMode {
            case .competitive: return (baseDiscovery, .competitiveFirstFinder)
            case .collaborative: return (baseDiscovery, .collaborativeSharedFinder)
            }
        case .acceptedLate:
            // A collaborative game reaches `.acceptedLate` only through the server's invalid-participant
            // rejection (§3.1.1 item 24: the partner who holds the plate has left). Nobody won a race
            // there, so the find settles under the same label as a shared one.
            guard gameMode == .competitive else {
                return xpNetAndReason(
                    finalOutcome: .acceptedShared,
                    gameMode: gameMode,
                    tripMode: tripMode,
                    rewards: rewards
                )
            }
            return (baseDiscovery, .competitiveLateFinder)
        case .acceptedShared:
            // A solo trip's game is collaborative by construction, so the sync path resolves every
            // solo find as `.acceptedShared`. Without this the settled row reads
            // `collaborative_shared_finder` while the provisional row this settles reads
            // `solo_new_discovery`, and one find surfaces in the ledger as both a "collab" and a
            // "solo" award. Same amount, same rule as `.acceptedFirst` — only the label.
            if tripMode == .solo {
                return (baseDiscovery, .soloNewDiscovery)
            }
            return (baseDiscovery, .collaborativeSharedFinder)
        }
    }
}
