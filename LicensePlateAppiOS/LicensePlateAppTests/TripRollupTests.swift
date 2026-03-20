//
//  TripRollupTests.swift
//  LicensePlateAppTests
//
//  Trip/Game Separation Step 1 — TripRollup.build from session, games, discoveries.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripRollupTests {

    @Test func buildWithEmptyGamesReturnsZeroCountsAndNilGoal() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Empty",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            participants: [TripParticipant(userId: "u1", role: .owner, joinedAt: Date())]
        )
        let rollup = TripRollup.build(session: session, games: [], discoveries: [])
        #expect(rollup.gameCount == 0)
        #expect(rollup.participantCount == 1)
        #expect(rollup.totalDiscoveryCount == 0)
        #expect(rollup.primaryGameDiscoveryCount == 0)
        #expect(rollup.primaryGameCompletionGoal == nil)
    }

    @Test func buildWithOneGameAndDiscoveriesSetsPrimaryGameCounts() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Solo",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            participants: [TripParticipant(userId: "u1", role: .owner, joinedAt: Date())]
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: Date(),
            endedAt: nil,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue)
        )
        let discoveries: [GameDiscovery] = [
            GameDiscovery(gameInstanceId: gameId, participantId: "u1", targetId: "us-ca", inputMethod: .list),
            GameDiscovery(gameInstanceId: gameId, participantId: "u1", targetId: "us-ny", inputMethod: .list)
        ]
        let rollup = TripRollup.build(session: session, games: [game], discoveries: discoveries)
        #expect(rollup.gameCount == 1)
        #expect(rollup.participantCount == 1)
        #expect(rollup.totalDiscoveryCount == 2)
        #expect(rollup.primaryGameDiscoveryCount == 2)
        // primaryGameCompletionGoal is nil when game has no licensePlateConfig payload (test game has no payload)
        #expect(rollup.primaryGameCompletionGoal == nil)
    }
}
