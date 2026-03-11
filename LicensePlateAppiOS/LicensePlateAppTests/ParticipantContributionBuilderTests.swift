//
//  ParticipantContributionBuilderTests.swift
//  LicensePlateAppTests
//
//  Step 06.5.5 — ParticipantContributionBuilder: contribution summary from discoveries + credits.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ParticipantContributionBuilderTests {

    private func makeDiscovery(
        id: String = UUID().uuidString,
        participantId: String,
        targetId: String = "region-1",
        gameInstanceId: UUID = UUID(),
        discoveredAt: Date = Date()
    ) -> GameDiscovery {
        GameDiscovery(
            id: id,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: discoveredAt,
            inputMethod: .list
        )
    }

    @Test func contributionSummaryEmptyDiscoveriesEmptyCredits() async throws {
        let result = ParticipantContributionBuilder.contributionSummary(discoveries: [], credits: [])
        #expect(result.isEmpty)
    }

    @Test func contributionSummarySoloOneDiscovery() async throws {
        let d = makeDiscovery(participantId: "user1", targetId: "us-ca")
        let credits = [
            GameCredit(discoveryId: d.id, participantId: "user1", creditType: .full, weight: 1.0)
        ]
        let result = ParticipantContributionBuilder.contributionSummary(discoveries: [d], credits: credits)
        #expect(result.count == 1)
        #expect(result[0].participantId == "user1")
        #expect(result[0].discoveryCount == 1)
        #expect(result[0].weightedScore == 1.0)
        #expect(result[0].firstFindCount == 1)
    }

    @Test func contributionSummaryCollaborativeTwoFindersSameTarget() async throws {
        let base = Date()
        let d1 = makeDiscovery(participantId: "user1", targetId: "us-ca", discoveredAt: base)
        let d2 = makeDiscovery(participantId: "user2", targetId: "us-ca", discoveredAt: base.addingTimeInterval(10))
        let credits = [
            GameCredit(discoveryId: d1.id, participantId: "user1", creditType: .shared, weight: 0.5),
            GameCredit(discoveryId: d1.id, participantId: "user2", creditType: .shared, weight: 0.5)
        ]
        let result = ParticipantContributionBuilder.contributionSummary(discoveries: [d1, d2], credits: credits)
        #expect(result.count == 2)
        let byUser = Dictionary(uniqueKeysWithValues: result.map { ($0.participantId, $0) })
        #expect(byUser["user1"]?.discoveryCount == 1)
        #expect(byUser["user2"]?.discoveryCount == 1)
        #expect(byUser["user1"]?.weightedScore == 0.5)
        #expect(byUser["user2"]?.weightedScore == 0.5)
        #expect(byUser["user1"]?.firstFindCount == 1)
        #expect(byUser["user2"]?.firstFindCount == 0)
    }

    @Test func contributionSummaryEmptyCreditsUsesDiscoveryCountAsScore() async throws {
        let d1 = makeDiscovery(participantId: "user1", targetId: "us-ca")
        let d2 = makeDiscovery(participantId: "user1", targetId: "us-ny")
        let result = ParticipantContributionBuilder.contributionSummary(discoveries: [d1, d2], credits: [])
        #expect(result.count == 1)
        #expect(result[0].participantId == "user1")
        #expect(result[0].discoveryCount == 2)
        #expect(result[0].weightedScore == 2.0)
        #expect(result[0].firstFindCount == 2)
    }

    @Test func contributionSummaryMultipleTargetsFirstFindCountPerTarget() async throws {
        let base = Date()
        let d1 = makeDiscovery(participantId: "alice", targetId: "us-ca", discoveredAt: base)
        let d2 = makeDiscovery(participantId: "bob", targetId: "us-ca", discoveredAt: base.addingTimeInterval(5))
        let d3 = makeDiscovery(participantId: "bob", targetId: "us-ny", discoveredAt: base.addingTimeInterval(10))
        let credits = [
            GameCredit(discoveryId: d1.id, participantId: "alice", creditType: .shared, weight: 0.5),
            GameCredit(discoveryId: d1.id, participantId: "bob", creditType: .shared, weight: 0.5),
            GameCredit(discoveryId: d3.id, participantId: "bob", creditType: .full, weight: 1.0)
        ]
        let result = ParticipantContributionBuilder.contributionSummary(discoveries: [d1, d2, d3], credits: credits)
        #expect(result.count == 2)
        let byUser = Dictionary(uniqueKeysWithValues: result.map { ($0.participantId, $0) })
        #expect(byUser["alice"]?.firstFindCount == 1)
        #expect(byUser["bob"]?.firstFindCount == 1)
        #expect(byUser["bob"]?.discoveryCount == 2)
    }
}
