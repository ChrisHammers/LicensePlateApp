//
//  TripSummaryBuilder.swift
//  LicensePlateApp
//
//  Step 07 — Build rich trip summary from session, games, discoveries, and credits. Pure logic; no persistence.
//

import Foundation

enum TripSummaryBuilder {

    /// Build a rich summary for a completed trip. Use discoveries and credits from LegacyTripAdapter when session has legacyTripId; otherwise pass empty arrays.
    static func build(
        session: TripSession,
        games: [GameInstance],
        discoveries: [GameDiscovery],
        credits: [GameCredit]
    ) -> TripSummary {
        let participantCount = session.participants.count
        let gameCount = games.count
        let totalDiscoveryCount = discoveries.count

        var gameItems: [TripSummaryGameItem] = []
        for game in games {
            let gameDiscoveries = discoveries.filter { $0.gameInstanceId == game.id }
            let gameCredits = credits.filter { credit in
                gameDiscoveries.contains { $0.id == credit.discoveryId }
            }
            let projection = DiscoveryCreditProjectionService.project(
                discoveries: gameDiscoveries,
                credits: gameCredits.isEmpty ? nil : gameCredits
            )
            gameItems.append(TripSummaryGameItem(
                gameInstanceId: game.id,
                definitionId: game.definitionId,
                discoveryCount: gameDiscoveries.count,
                startedAt: game.startedAt,
                endedAt: game.endedAt,
                firstDiscoveries: projection.targetSummaries
            ))
        }

        let participantContributions = ParticipantContributionBuilder.contributionSummary(
            discoveries: discoveries,
            credits: credits
        )

        let discoveryProjection: DiscoveryCreditProjection? = discoveries.isEmpty ? nil : DiscoveryCreditProjectionService.project(
            discoveries: discoveries,
            credits: credits.isEmpty ? nil : credits
        )

        return TripSummary(
            sessionId: session.id,
            tripName: session.name,
            status: session.status,
            endedAt: session.endedAt,
            startedAt: session.startedAt,
            participantCount: participantCount,
            gameCount: gameCount,
            totalDiscoveryCount: totalDiscoveryCount,
            games: gameItems,
            participantContributions: participantContributions,
            discoveryProjection: discoveryProjection,
            locationMetadata: nil
        )
    }
}
