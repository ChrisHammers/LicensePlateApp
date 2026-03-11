//
//  TripSummaryBuilderTests.swift
//  LicensePlateAppTests
//
//  Step 07 — TripSummaryBuilder: build summary from session, games, discoveries, credits.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSummaryBuilderTests {

    @Test func buildWithEmptyDiscoveriesReturnsSummaryWithCounts() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Solo Trip",
            status: .ended,
            mode: .solo,
            endedAt: Date().addingTimeInterval(-100),
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
        let gameId = UUID()
        let game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            startedAt: Date().addingTimeInterval(-200),
            endedAt: Date().addingTimeInterval(-100),
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        let summary = TripSummaryBuilder.build(
            session: session,
            games: [game],
            discoveries: [],
            credits: []
        )
        #expect(summary.sessionId == sessionId)
        #expect(summary.tripName == "Solo Trip")
        #expect(summary.status == .ended)
        #expect(summary.participantCount == 1)
        #expect(summary.gameCount == 1)
        #expect(summary.totalDiscoveryCount == 0)
        #expect(summary.games.count == 1)
        #expect(summary.games[0].definitionId == "license_plate")
        #expect(summary.games[0].discoveryCount == 0)
        #expect(summary.participantContributions.isEmpty)
        #expect(summary.discoveryProjection == nil)
    }

    @Test func buildWithDiscoveriesAndCreditsReturnsContributionsAndProjection() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Multi Trip",
            status: .ended,
            mode: .solo,
            endedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
        let game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        let d1 = GameDiscovery(
            gameInstanceId: gameId,
            participantId: "user1",
            targetId: "CA",
            inputMethod: .list
        )
        let d2 = GameDiscovery(
            gameInstanceId: gameId,
            participantId: "user1",
            targetId: "TX",
            inputMethod: .list
        )
        let credits: [GameCredit] = [
            GameCredit(discoveryId: d1.id, participantId: "user1", creditType: .full, weight: 1.0),
            GameCredit(discoveryId: d2.id, participantId: "user1", creditType: .full, weight: 1.0)
        ]
        let summary = TripSummaryBuilder.build(
            session: session,
            games: [game],
            discoveries: [d1, d2],
            credits: credits
        )
        #expect(summary.totalDiscoveryCount == 2)
        #expect(summary.games[0].discoveryCount == 2)
        #expect(summary.participantContributions.count == 1)
        #expect(summary.participantContributions[0].participantId == "user1")
        #expect(summary.participantContributions[0].discoveryCount == 2)
        #expect(summary.participantContributions[0].weightedScore == 2.0)
        #expect(summary.discoveryProjection != nil)
        #expect(summary.discoveryProjection!.targetSummaries.count == 2)
    }

    // MARK: - Step 07.5 Per-game config

    @Test func buildWithLicensePlateConfigIncludesCompletionGoalAndProgressDescription() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Config Trip",
            status: .ended,
            mode: .solo,
            endedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner)],
            enabledCountryRawValues: ["United States"]
        )
        let lpConfig = LicensePlateGameConfig(
            regionScope: .usOnly,
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: false)
        )
        let payloadData = try JSONEncoder().encode(lpConfig)
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig(),
            gameSpecificPayloadType: GameType.licensePlate.rawValue,
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: payloadData
        )
        let summary = TripSummaryBuilder.build(
            session: session,
            games: [game],
            discoveries: [],
            credits: []
        )
        #expect(summary.games.count == 1)
        #expect(summary.games[0].completionGoal == 50)
        #expect(summary.games[0].progressDescription == "0 / 50 US regions")
    }

    @Test func buildWithoutLicensePlatePayloadLeavesCompletionGoalAndProgressNil() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "No Config",
            status: .ended,
            mode: .solo,
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
        let game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: [], credits: [])
        #expect(summary.games[0].completionGoal == nil)
        #expect(summary.games[0].progressDescription == nil)
    }
}
