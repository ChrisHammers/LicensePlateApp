//
//  CombinedGameAssembler.swift
//  LicensePlateApp
//
//  Step 06 — Builds game instances for a trip session from combined game configuration. No persistence; caller uses repositories.
//

import Foundation

/// Assembles one GameInstance per enabled game type for a given TripSession. Caller persists via GameInstanceRepository.
enum CombinedGameAssembler {
    /// Create one GameInstance per enabled (and available) game type, all linked to the given session.
    /// - Parameters:
    ///   - session: The trip session these games belong to.
    ///   - config: Which game types are enabled; only available types are used.
    /// - Returns: Domain GameInstance values; caller must persist via GameInstanceRepository.
    static func assemble(session: TripSession, config: CombinedGameConfiguration) -> [GameInstance] {
        let types = config.availableEnabledTypes
        guard !types.isEmpty else { return [] }

        let startedAt = session.startedAt ?? Date()
        return types.map { gameType in
            GameInstance(
                definitionId: gameType.rawValue,
                sessionId: session.id,
                startedAt: startedAt,
                endedAt: session.endedAt,
                ruleSet: gameType.defaultRuleSet()
            )
        }
    }
}
