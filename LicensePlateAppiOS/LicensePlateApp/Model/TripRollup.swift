//
//  TripRollup.swift
//  LicensePlateApp
//
//  Trip/Game Separation Step 1 — Trip-level rollup projection for list/summary. Board progress is game-scoped via primary game fields.
//

import Foundation

/// Trip-level rollup for active list and summary. Use for display only; board and progress are owned by GameInstance and derived from events.
struct TripRollup: Sendable {
    var gameCount: Int
    var participantCount: Int
    var totalDiscoveryCount: Int
    /// Discoveries for the primary (license-plate-first) game.
    var primaryGameDiscoveryCount: Int
    /// Completion goal for primary game from its config; nil if not license-plate or config missing.
    var primaryGameCompletionGoal: Int?

    /// Build rollup from session, its games, and all discoveries for the session.
    static func build(session: TripSession, games: [GameInstance], discoveries: [GameDiscovery]) -> TripRollup {
        let participantCount = session.participants.count
        let gameCount = games.count
        let totalDiscoveryCount = discoveries.count
        let primary = games.first(where: { $0.definitionId == GameType.licensePlate.rawValue }) ?? games.first
        let primaryGameDiscoveryCount = primary.map { g in discoveries.filter { $0.gameInstanceId == g.id }.count } ?? 0
        let primaryGameCompletionGoal = primary.flatMap { $0.licensePlateConfig() }.map { LicensePlateScopeCalculator.completionGoal(for: $0) }
        return TripRollup(
            gameCount: gameCount,
            participantCount: participantCount,
            totalDiscoveryCount: totalDiscoveryCount,
            primaryGameDiscoveryCount: primaryGameDiscoveryCount,
            primaryGameCompletionGoal: primaryGameCompletionGoal
        )
    }
}
