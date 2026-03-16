//
//  TripSummaryBuilder.swift
//  LicensePlateApp
//
//  Step 07 — Build rich trip summary from session, games, discoveries, and credits. Pure logic; no persistence.
//  Step 07.5 — completionGoal and progressDescription from game config (license plate).
//

import Foundation

enum TripSummaryBuilder {

    /// Build a rich summary for a completed trip. Use discoveries and credits from TripActivityEventRepository (and computed credits).
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
            let (completionGoal, progressDescription) = Self.progressFromGame(game, discoveryCount: gameDiscoveries.count)
            gameItems.append(TripSummaryGameItem(
                gameInstanceId: game.id,
                definitionId: game.definitionId,
                discoveryCount: gameDiscoveries.count,
                startedAt: game.startedAt,
                endedAt: game.endedAt,
                firstDiscoveries: projection.targetSummaries,
                completionGoal: completionGoal,
                progressDescription: progressDescription
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

    /// Step 07.5 — Derive completion goal and progress description from game config (license plate only).
    private static func progressFromGame(_ game: GameInstance, discoveryCount: Int) -> (Int?, String?) {
        guard let lpConfig = game.licensePlateConfig() else { return (nil, nil) }
        let goal = LicensePlateScopeCalculator.completionGoal(for: lpConfig)
        let label = progressLabel(for: lpConfig.regionScope)
        return (goal, "\(discoveryCount) / \(goal) \(label)")
    }

    private static func progressLabel(for scope: RegionScope) -> String {
        switch scope {
        case .usOnly: return "US regions"
        case .canadaOnly: return "Canadian regions"
        case .mexicoOnly: return "Mexican regions"
        case .northAmerica: return "North American regions"
        }
    }
}
