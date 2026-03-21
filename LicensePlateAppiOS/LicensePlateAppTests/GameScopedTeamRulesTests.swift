//
//  GameScopedTeamRulesTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.5 Phase B.1 — Team attribution on credits uses game-scoped `TripTeam` lists only.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameScopedTeamRulesTests {

    private let gameInstanceId1 = UUID()
    private let gameInstanceId2 = UUID()

    private func discovery(
        gameInstanceId: UUID,
        participantId: String,
        targetId: String = "CA",
        offset: TimeInterval = 0
    ) -> GameDiscovery {
        GameDiscovery(
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: Date().addingTimeInterval(offset),
            inputMethod: .list
        )
    }

    /// Same participant id on two different games: each `creditsForDiscoveries` call must use only that call's `teams` argument.
    @Test func creditsForDiscoveriesEachGameUsesItsOwnTeams() {
        let teamsGame1 = [TripTeam(id: "car-a", name: "Car A", participantUserIds: ["driver1"])]
        let teamsGame2 = [TripTeam(id: "car-b", name: "Car B", participantUserIds: ["driver1"])]
        let d1 = discovery(gameInstanceId: gameInstanceId1, participantId: "driver1")
        let d2 = discovery(gameInstanceId: gameInstanceId2, participantId: "driver1")
        let credits1 = DiscoveryRulesEngine.creditsForDiscoveries(
            mode: .competitive,
            discoveriesByTarget: ["CA": [d1]],
            teams: teamsGame1
        )
        let credits2 = DiscoveryRulesEngine.creditsForDiscoveries(
            mode: .competitive,
            discoveriesByTarget: ["CA": [d2]],
            teams: teamsGame2
        )
        #expect(credits1.count == 1)
        #expect(credits2.count == 1)
        #expect(credits1[0].teamId == "car-a")
        #expect(credits2[0].teamId == "car-b")
    }

    /// Engine/calculator never consult trip roster; team ids come only from the `teams` parameter passed for that game.
    @Test func evaluateDiscoverySubmissionCreditsUsePassedTeamsOnly() {
        let teams = [TripTeam(id: "game-team", name: "Squad", participantUserIds: ["user1"])]
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [],
            candidateParticipantId: "user1",
            candidateTargetId: "TX",
            gameInstanceId: gameInstanceId1,
            inputMethod: .list,
            occurredAt: Date(),
            teams: teams,
            riskContext: nil
        )
        #expect(result.outcome == .newCredit)
        #expect(result.creditsToAssign?.first?.teamId == "game-team")
    }
}
