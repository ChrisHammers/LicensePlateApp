//
//  GameCreditCalculator.swift
//  LicensePlateApp
//
//  Step 6.9.1 — Compute GameCredit list from game mode and discoveries (collaborative vs competitive).
//

import Foundation

/// Produces the list of GameCredit to assign for a discovery, based on game mode. No persistence; caller passes discoveries.
enum GameCreditCalculator {

    /// Returns credits to assign for the given discovery. Caller provides existing discoveries for the same target (e.g. same targetId).
    /// - Collaborative: one shared credit per finder for this target (all finders get credit), weight 1.0 / finderCount.
    /// - Competitive: one full credit for the discovering participant, weight 1.0.
    /// - Parameter teams: Game-scoped team definitions; `teamId` on each credit is resolved from these lists only (never trip roster).
    static func credits(
        for mode: GameMode,
        discovery: GameDiscovery,
        existingDiscoveriesForTarget: [GameDiscovery],
        teams: [TripTeam] = []
    ) -> [GameCredit] {
        let creditType = GameModeRulesEngine.creditType(for: mode)
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
                    weight: weight,
                    teamId: Self.teamId(for: participantId, teams: teams)
                )
            }
        case .full:
            return [
                GameCredit(
                    discoveryId: discovery.id,
                    participantId: discovery.participantId,
                    creditType: .full,
                    weight: 1.0,
                    teamId: Self.teamId(for: discovery.participantId, teams: teams)
                )
            ]
        }
    }

    /// First team in `teams` whose `participantUserIds` contains `participantId`.
    private static func teamId(for participantId: String, teams: [TripTeam]) -> String? {
        guard !teams.isEmpty else { return nil }
        return teams.first { $0.participantUserIds.contains(participantId) }?.id
    }
}
