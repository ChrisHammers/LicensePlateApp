//
//  TripSummaryBuilder.swift
//  LicensePlateApp
//
//  Step 07 — Build rich trip summary from session, games, discoveries, and credits. Pure logic; no persistence.
//  Step 07.5 — completionGoal and progressDescription from game config (license plate).
//

import Foundation

enum TripSummaryBuilder {

    /// Per-game credits for trip-wide summary / Travel Log / trip dashboard — same rules as `DiscoveryRulesEngine.creditsForDiscoveries` per `GameInstance`.
    static func creditsForTripSummary(games: [GameInstance], discoveries: [GameDiscovery]) -> [GameCredit] {
        var allCredits: [GameCredit] = []
        allCredits.reserveCapacity(discoveries.count)
        for game in games {
            let gameDiscoveries = discoveries.filter { $0.gameInstanceId == game.id }
            let discoveriesByTarget = Dictionary(grouping: gameDiscoveries, by: \.targetId)
            let gameCredits = DiscoveryRulesEngine.creditsForDiscoveries(
                mode: game.commonConfig.gameMode,
                discoveriesByTarget: discoveriesByTarget,
                teams: game.teams
            )
            allCredits.append(contentsOf: gameCredits)
        }
        return allCredits
    }

    /// Build summary by deriving credits from discoveries (Travel Log and trip dashboard entry point).
    static func build(session: TripSession, games: [GameInstance], discoveries: [GameDiscovery]) -> TripSummary {
        let credits = creditsForTripSummary(games: games, discoveries: discoveries)
        return build(session: session, games: games, discoveries: discoveries, credits: credits)
    }

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
        let gameModeByInstanceId = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.commonConfig.gameMode) })

        var gameItems: [TripSummaryGameItem] = []
        for game in games {
            let gameDiscoveries = discoveries.filter { $0.gameInstanceId == game.id }
            let gameCredits = credits.filter { credit in
                gameDiscoveries.contains { $0.id == credit.discoveryId }
            }
            let projection = DiscoveryCreditProjectionService.project(
                discoveries: gameDiscoveries,
                credits: gameCredits.isEmpty ? nil : gameCredits,
                gameModeByInstanceId: gameModeByInstanceId
            )
            let (scopedFoundCount, completionGoal, progressDescription) = Self.progressFromGame(
                game,
                discoveries: gameDiscoveries
            )
            gameItems.append(TripSummaryGameItem(
                gameInstanceId: game.id,
                definitionId: game.definitionId,
                discoveryCount: scopedFoundCount,
                startedAt: game.startedAt,
                endedAt: game.endedAt,
                firstDiscoveries: projection.targetSummaries,
                completionGoal: completionGoal,
                progressDescription: progressDescription,
                gameMode: game.commonConfig.gameMode,
                teamSummary: Self.teamSummary(for: game.teams)
            ))
        }

        let rawContributions = ParticipantContributionBuilder.contributionSummary(
            discoveries: discoveries,
            credits: credits
        )
        let mergedContributions = TripRosterContributionMerge.merge(
            roster: session.participants,
            contributions: rawContributions
        )
        let rankedParticipants = TripParticipantRanking.rankContributions(mergedContributions)

        let discoveryProjection: DiscoveryCreditProjection? = discoveries.isEmpty ? nil : DiscoveryCreditProjectionService.project(
            discoveries: discoveries,
            credits: credits.isEmpty ? nil : credits,
            gameModeByInstanceId: gameModeByInstanceId
        )

        return TripSummary(
            sessionId: session.id,
            tripName: session.name,
            tripMode: session.mode,
            status: session.status,
            endedAt: session.endedAt,
            startedAt: session.startedAt,
            participantCount: participantCount,
            gameCount: gameCount,
            totalDiscoveryCount: totalDiscoveryCount,
            games: gameItems,
            rankedParticipants: rankedParticipants,
            discoveryProjection: discoveryProjection,
            locationMetadata: nil
        )
    }

    /// Non-empty teams → short summary for UI; nil when no teams.
    private static func teamSummary(for teams: [TripTeam]) -> String? {
        guard !teams.isEmpty else { return nil }
        if teams.count == 1 {
            let name = teams[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "1 team".localized : name
        }
        return "%d teams".localized(teams.count)
    }

    /// Step 07.5 — Derive completion goal and progress description from game config (license plate only).
    /// Found count is unique in-scope target IDs (territory / DC filters applied), not raw discovery rows.
    private static func progressFromGame(
        _ game: GameInstance,
        discoveries: [GameDiscovery]
    ) -> (scopedFoundCount: Int, completionGoal: Int?, progressDescription: String?) {
        guard let lpConfig = game.licensePlateConfig() else {
            return (discoveries.count, nil, nil)
        }
        let goal = LicensePlateScopeCalculator.completionGoal(for: lpConfig)
        let scopedFound = LicensePlateScopeCalculator.scopedUniqueFoundCount(
            discoveries: discoveries,
            config: lpConfig
        )
        let label = progressLabel(for: lpConfig.selectedCountries)
        return (scopedFound, goal, "\(scopedFound) / \(goal) \(label)")
    }

    private static func progressLabel(for countries: [PlateRegion.Country]) -> String {
        let set = Set(countries)
        if set == [.unitedStates] { return "US regions" }
        if set == [.canada] { return "Canadian regions" }
        if set == [.mexico] { return "Mexican regions" }
        if set == [.unitedStates, .canada, .mexico] { return "North American regions" }
        let names = countries.map { country in
            switch country {
            case .unitedStates: return "US"
            case .canada: return "Canada"
            case .mexico: return "Mexico"
            }
        }
        return "\(names.joined(separator: " + ")) regions"
    }
}
