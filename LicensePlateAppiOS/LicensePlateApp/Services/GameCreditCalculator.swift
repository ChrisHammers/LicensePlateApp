//
//  GameCreditCalculator.swift
//  LicensePlateApp
//
//  Step 05 — compute GameCredit list from trip mode and discoveries (collaborative vs competitive/solo).
//

import Foundation

/// Produces the list of GameCredit to assign for a discovery, based on trip mode. No persistence; caller passes discoveries.
enum GameCreditCalculator {

    /// Returns credits to assign for the given discovery. Caller provides existing discoveries for the same target (e.g. same targetId).
    /// - Collaborative: one shared credit per finder for this target (all finders get credit), weight 1.0 / finderCount.
    /// - Solo / competitive / combined: one full credit for the discovering participant, weight 1.0.
    static func credits(
        for mode: TripMode,
        discovery: GameDiscovery,
        existingDiscoveriesForTarget: [GameDiscovery]
    ) -> [GameCredit] {
        let creditType = TripModeRulesEngine.creditType(for: mode)
        switch creditType {
        case .shared:
            let allFinderIds = Set(existingDiscoveriesForTarget.map(\.participantId))
                .union([discovery.participantId])
            let count = Double(allFinderIds.count)
            let weight = count > 0 ? 1.0 / count : 1.0
            return allFinderIds.map { participantId in
                GameCredit(
                    discoveryId: discovery.id,
                    participantId: participantId,
                    creditType: .shared,
                    weight: weight
                )
            }
        case .full:
            return [
                GameCredit(
                    discoveryId: discovery.id,
                    participantId: discovery.participantId,
                    creditType: .full,
                    weight: 1.0
                )
            ]
        }
    }
}
