//
//  GameScopedScoringProjectionTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.5 Phase B.2 — Trip-level rollups do not merge targets across games.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameScopedScoringProjectionTests {

    @Test func projectionSameTargetTwoGamesProducesTwoSummaries() {
        let game1 = UUID()
        let game2 = UUID()
        let t = Date()
        let d1 = GameDiscovery(
            gameInstanceId: game1,
            participantId: "p1",
            targetId: "CA",
            discoveredAt: t,
            inputMethod: .list
        )
        let d2 = GameDiscovery(
            gameInstanceId: game2,
            participantId: "p2",
            targetId: "CA",
            discoveredAt: t.addingTimeInterval(1),
            inputMethod: .list
        )
        let projection = DiscoveryCreditProjectionService.project(discoveries: [d1, d2], credits: nil)
        #expect(projection.targetSummaries.count == 2)
        let rowIds = Set(projection.targetSummaries.map(\.id))
        #expect(rowIds == Set(["\(game1.uuidString)_CA", "\(game2.uuidString)_CA"]))
    }

    @Test func contributionFirstFindCountPerGameTarget() {
        let game1 = UUID()
        let game2 = UUID()
        let t = Date()
        let d1 = GameDiscovery(gameInstanceId: game1, participantId: "solo", targetId: "CA", discoveredAt: t, inputMethod: .list)
        let d2 = GameDiscovery(gameInstanceId: game2, participantId: "solo", targetId: "CA", discoveredAt: t.addingTimeInterval(1), inputMethod: .list)
        let c1 = GameCredit(discoveryId: d1.id, participantId: "solo", creditType: .full, weight: 1.0)
        let c2 = GameCredit(discoveryId: d2.id, participantId: "solo", creditType: .full, weight: 1.0)
        let contributions = ParticipantContributionBuilder.contributionSummary(discoveries: [d1, d2], credits: [c1, c2])
        #expect(contributions.count == 1)
        #expect(contributions[0].participantId == "solo")
        #expect(contributions[0].firstFindCount == 2)
        #expect(contributions[0].discoveryCount == 2)
        #expect(contributions[0].weightedScore == 2.0)
    }
}
