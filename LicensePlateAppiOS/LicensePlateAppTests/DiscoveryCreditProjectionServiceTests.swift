//
//  DiscoveryCreditProjectionServiceTests.swift
//  LicensePlateAppTests
//
//  Step 06.5.5 — DiscoveryCreditProjectionService: projection from discoveries + credits to UI summaries.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoveryCreditProjectionServiceTests {

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

    @Test func projectEmptyDiscoveries() async throws {
        let result = DiscoveryCreditProjectionService.project(discoveries: [], credits: nil)
        #expect(result.participantScores.isEmpty)
        #expect(result.targetSummaries.isEmpty)
    }

    @Test func projectSingleDiscoveryNoCreditsUsesImplicitFullCredit() async throws {
        let d = makeDiscovery(participantId: "user1", targetId: "us-ca")
        let result = DiscoveryCreditProjectionService.project(discoveries: [d], credits: nil)
        #expect(result.targetSummaries.count == 1)
        #expect(result.targetSummaries[0].targetId == "us-ca")
        #expect(result.targetSummaries[0].firstFinderParticipantId == "user1")
        #expect(result.targetSummaries[0].summaryLabel.contains("user1"))
        #expect(result.participantScores.count == 1)
        #expect(result.participantScores[0].participantId == "user1")
        #expect(result.participantScores[0].weightedScore == 1.0)
        #expect(result.participantScores[0].creditedDiscoveryCount == 1)
    }

    @Test func projectTwoDiscoveriesSameTargetFirstFinderInSummary() async throws {
        let base = Date()
        let d1 = makeDiscovery(participantId: "user1", targetId: "us-ca", discoveredAt: base)
        let d2 = makeDiscovery(participantId: "user2", targetId: "us-ca", discoveredAt: base.addingTimeInterval(10))
        let result = DiscoveryCreditProjectionService.project(discoveries: [d1, d2], credits: nil)
        #expect(result.targetSummaries.count == 1)
        #expect(result.targetSummaries[0].firstFinderParticipantId == "user1")
        #expect(Set(result.targetSummaries[0].allFinderParticipantIds) == Set(["user1", "user2"]))
        #expect(result.targetSummaries[0].summaryLabel == "2 finders")
    }

    @Test func projectWithCreditsUsesWeightsForParticipantScores() async throws {
        let d1 = makeDiscovery(participantId: "user1", targetId: "us-ca")
        let d2 = makeDiscovery(participantId: "user2", targetId: "us-ca")
        let credits = [
            GameCredit(discoveryId: d1.id, participantId: "user1", creditType: .shared, weight: 0.5),
            GameCredit(discoveryId: d1.id, participantId: "user2", creditType: .shared, weight: 0.5)
        ]
        let result = DiscoveryCreditProjectionService.project(discoveries: [d1, d2], credits: credits)
        #expect(result.participantScores.count == 2)
        let byUser = Dictionary(uniqueKeysWithValues: result.participantScores.map { ($0.participantId, $0) })
        #expect(byUser["user1"]?.weightedScore == 0.5)
        #expect(byUser["user2"]?.weightedScore == 0.5)
        #expect(byUser["user1"]?.creditedDiscoveryCount == 1)
        #expect(byUser["user2"]?.creditedDiscoveryCount == 1)
    }

    @Test func projectMultipleTargetsProducesOneSummaryPerTarget() async throws {
        let d1 = makeDiscovery(participantId: "user1", targetId: "us-ca")
        let d2 = makeDiscovery(participantId: "user1", targetId: "us-ny")
        let result = DiscoveryCreditProjectionService.project(discoveries: [d1, d2], credits: nil)
        #expect(result.targetSummaries.count == 2)
        #expect(Set(result.targetSummaries.map(\.targetId)) == Set(["us-ca", "us-ny"]))
        #expect(result.participantScores.count == 1)
        #expect(result.participantScores[0].weightedScore == 2.0)
        #expect(result.participantScores[0].creditedDiscoveryCount == 2)
    }
}
