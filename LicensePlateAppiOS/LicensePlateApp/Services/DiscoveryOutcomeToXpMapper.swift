//
//  DiscoveryOutcomeToXpMapper.swift
//  LicensePlateApp
//
//  Testable mapping from canonical resolution to final XP and projection hints.
//

import Foundation

struct DiscoveryXpMapping: Sendable, Equatable {
    var finalNetXp: Int
    var reasonCode: XpReasonCode
    /// Hint for UI when resolution has been applied.
    var resolvedXpPhase: DiscoveryXpProjectionPhase
}

enum DiscoveryOutcomeToXpMapper {

    static func map(
        resolution: DiscoveryResolution,
        gameMode: GameMode,
        tripMode: TripMode? = nil
    ) -> DiscoveryXpMapping {
        let award = XpAwardRuleEngine.compute(from: resolution, gameMode: gameMode, tripMode: tripMode)
        let phase: DiscoveryXpProjectionPhase = resolution.finalOutcome == .pending ? .provisional : .final
        return DiscoveryXpMapping(
            finalNetXp: award.xpNet,
            reasonCode: award.xpReason,
            resolvedXpPhase: phase
        )
    }
}
