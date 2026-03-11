//
//  LegacyTripAdapter.swift
//  LicensePlateApp
//
//  Gameplay model foundation — maps legacy Trip to new TripSession + GameInstance + discoveries (read-only; no persistence).
//

import Foundation

/// Result of adapting a legacy Trip to the new gameplay model. Read-only; nothing is persisted.
struct LegacyTripAdapterResult {
    var session: TripSession
    var gameInstance: GameInstance
    var discoveries: [GameDiscovery]
    var credits: [GameCredit]
}

/// Maps legacy Trip and trip.foundRegions to TripSession, GameInstance, GameDiscovery, and GameCredit.
/// Handles nil foundBy (treat as solo). Does not modify or persist anything.
enum LegacyTripAdapter {
    /// Default game definition id for license-plate trips.
    static let licensePlateGameDefinitionId = "license_plate"

    /// Build TripSession, GameInstance, discoveries, and credits from a legacy Trip.
    static func adapt(_ trip: Trip) -> LegacyTripAdapterResult {
        let sessionId = trip.id
        let status: TripStatus
        if trip.isTripEnded {
            status = .ended
        } else if trip.startedAt != nil {
            status = .active
        } else {
            status = .draft
        }

        let participantIds = Set(trip.foundRegions.compactMap { $0.foundBy }).union(trip.createdBy.map { [$0] } ?? [])
        let createdByUserId = trip.createdBy ?? "unknown"
        let participants: [TripParticipant] = participantIds.isEmpty
            ? [TripParticipant(userId: createdByUserId, role: .owner, joinedAt: trip.createdAt)]
            : participantIds.map { userId in
                TripParticipant(
                    userId: userId,
                    role: userId == createdByUserId ? .owner : .member,
                    joinedAt: trip.createdAt
                )
            }

        let session = TripSession(
            id: sessionId,
            name: trip.name,
            status: status,
            mode: participantIds.count <= 1 ? .solo : .collaborative,
            createdBy: trip.createdBy,
            startedAt: trip.startedAt,
            endedAt: trip.tripEndedAt,
            endedBy: trip.tripEndedBy,
            participants: participants,
            teams: [],
            legacyTripId: trip.id,
            enabledCountryRawValues: trip.enabledCountryStrings.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        )

        let ruleSet = GameRuleSet(gameDefinitionId: Self.licensePlateGameDefinitionId)
        let gameInstanceId = UUID()
        let gameInstance = GameInstance(
            id: gameInstanceId,
            definitionId: Self.licensePlateGameDefinitionId,
            sessionId: sessionId,
            startedAt: trip.startedAt ?? trip.createdAt,
            endedAt: trip.tripEndedAt,
            ruleSet: ruleSet
        )

        var discoveries: [GameDiscovery] = []
        for fr in trip.foundRegions {
            let discoveryId = UUID().uuidString
            let participantId = fr.foundBy ?? createdByUserId
            let discovery = GameDiscovery(
                id: discoveryId,
                gameInstanceId: gameInstanceId,
                participantId: participantId,
                targetId: fr.regionID,
                discoveredAt: fr.foundAt,
                inputMethod: fr.inputMethod,
                location: fr.foundAtLocation
            )
            discoveries.append(discovery)
        }

        // Compute credits per target using trip mode (Step 06.5.5 — mode logic alignment).
        // Collaborative: use last discovery so all finders get shared credit. Full-credit modes: use first discovery so only first finder gets credit.
        var credits: [GameCredit] = []
        let discoveriesByTarget = Dictionary(grouping: discoveries, by: \.targetId)
        let isShared = TripModeRulesEngine.creditType(for: session.mode) == .shared
        for (_, targetDiscoveries) in discoveriesByTarget {
            let sorted = targetDiscoveries.sorted { $0.discoveredAt < $1.discoveredAt }
            guard let discovery = isShared ? sorted.last : sorted.first else { continue }
            let existing = isShared ? Array(sorted.dropLast()) : Array(sorted.dropFirst())
            let creditsForTarget = GameCreditCalculator.credits(
                for: session.mode,
                discovery: discovery,
                existingDiscoveriesForTarget: existing
            )
            credits.append(contentsOf: creditsForTarget)
        }

        return LegacyTripAdapterResult(
            session: session,
            gameInstance: gameInstance,
            discoveries: discoveries,
            credits: credits
        )
    }
}
