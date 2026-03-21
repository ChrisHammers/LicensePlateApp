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
            createdAt: Date().addingTimeInterval(-200),
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
        #expect(summary.tripMode == .solo)
        #expect(summary.status == .ended)
        #expect(summary.participantCount == 1)
        #expect(summary.gameCount == 1)
        #expect(summary.totalDiscoveryCount == 0)
        #expect(summary.games.count == 1)
        #expect(summary.games[0].definitionId == "license_plate")
        #expect(summary.games[0].discoveryCount == 0)
        #expect(summary.games[0].gameMode == .collaborative)
        #expect(summary.games[0].teamSummary == nil)
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
            mode: .multiplayer,
            createdAt: Date().addingTimeInterval(-100),
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
        #expect(summary.tripMode == .multiplayer)
        #expect(summary.totalDiscoveryCount == 2)
        #expect(summary.games[0].discoveryCount == 2)
        #expect(summary.games[0].gameMode == .collaborative)
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
            createdAt: Date().addingTimeInterval(-100),
            endedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
        let lpConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
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
        #expect(summary.games[0].gameMode == .collaborative)
        #expect(summary.games[0].teamSummary == nil)
    }

    @Test func buildWithoutLicensePlatePayloadLeavesCompletionGoalAndProgressNil() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "No Config",
            status: .ended,
            mode: .solo,
            createdAt: Date(),
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
        #expect(summary.games[0].gameMode == .collaborative)
        #expect(summary.games[0].teamSummary == nil)
    }

    @Test func buildReflectsGameModeFromCommonConfig() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Competitive run",
            status: .ended,
            mode: .solo,
            createdAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner)]
        )
        var config = CommonGameConfig()
        config.gameMode = .competitive
        let game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: config
        )
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: [], credits: [])
        #expect(summary.games[0].gameMode == .competitive)
    }

    @Test func buildWithTeamsSetsTeamSummary() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Team trip",
            status: .ended,
            mode: .multiplayer,
            createdAt: Date(),
            participants: [
                TripParticipant(userId: "a", role: .owner),
                TripParticipant(userId: "b", role: .member)
            ]
        )
        let teams = [
            TripTeam(name: "Team Red", participantUserIds: ["a"]),
            TripTeam(name: "Team Blue", participantUserIds: ["b"])
        ]
        let game = GameInstance(
            id: gameId,
            definitionId: "license_plate",
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            teams: teams
        )
        let summary = TripSummaryBuilder.build(session: session, games: [game], discoveries: [], credits: [])
        #expect(summary.games[0].teamSummary != nil)
        #expect(summary.tripMode == .multiplayer)
    }

    /// Step 6.9.5 — Same region id in two games: trip-level `discoveryProjection` keeps two rows keyed by game + target.
    @Test func buildTwoGamesSameTargetId_tripDiscoveryProjectionNotMerged() async throws {
        let sessionId = UUID()
        let gameId1 = UUID()
        let gameId2 = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Dual LP",
            status: .ended,
            mode: .multiplayer,
            createdAt: Date().addingTimeInterval(-100),
            endedAt: Date(),
            participants: [
                TripParticipant(userId: "u1", role: .owner),
                TripParticipant(userId: "u2", role: .member)
            ]
        )
        let game1 = GameInstance(
            id: gameId1,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        )
        let game2 = GameInstance(
            id: gameId2,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        )
        let d1 = GameDiscovery(
            gameInstanceId: gameId1,
            participantId: "u1",
            targetId: "CA",
            inputMethod: .list
        )
        let d2 = GameDiscovery(
            gameInstanceId: gameId2,
            participantId: "u2",
            targetId: "CA",
            inputMethod: .list
        )
        let credits: [GameCredit] = [
            GameCredit(discoveryId: d1.id, participantId: "u1", creditType: .full, weight: 1.0),
            GameCredit(discoveryId: d2.id, participantId: "u2", creditType: .full, weight: 1.0)
        ]
        let summary = TripSummaryBuilder.build(
            session: session,
            games: [game1, game2],
            discoveries: [d1, d2],
            credits: credits
        )
        #expect(summary.tripMode == .multiplayer)
        #expect(summary.games[0].gameMode == .collaborative)
        #expect(summary.games[1].gameMode == .collaborative)
        #expect(summary.discoveryProjection != nil)
        let projection = summary.discoveryProjection!
        #expect(projection.targetSummaries.count == 2)
        let rowIds = Set(projection.targetSummaries.map(\.id))
        #expect(rowIds == Set(["\(gameId1.uuidString)_CA", "\(gameId2.uuidString)_CA"]))
        let byUser = Dictionary(uniqueKeysWithValues: summary.participantContributions.map { ($0.participantId, $0.firstFindCount) })
        #expect(byUser["u1"] == 1)
        #expect(byUser["u2"] == 1)
    }
}
