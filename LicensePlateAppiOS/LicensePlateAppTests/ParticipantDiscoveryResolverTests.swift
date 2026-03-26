//
//  ParticipantDiscoveryResolverTests.swift
//  LicensePlateAppTests
//
//  Step 05 — ParticipantDiscoveryResolver: first finder, all finders, summary label.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ParticipantDiscoveryResolverTests {

    private func makeDiscovery(
        participantId: String,
        targetId: String = "region-1",
        discoveredAt: Date = Date(),
        gameInstanceId: UUID = UUID()
    ) -> GameDiscovery {
        GameDiscovery(
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: discoveredAt,
            inputMethod: .list
        )
    }

    @Test func summaryEmptyDiscoveries() async throws {
        let result = ParticipantDiscoveryResolver.summary(discoveries: [])
        #expect(result.firstFinderParticipantId == nil)
        #expect(result.allFinderParticipantIds.isEmpty)
        #expect(result.summaryLabel == "")
    }

    @Test func summaryOneFinder() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = ParticipantDiscoveryResolver.summary(discoveries: [discovery])
        #expect(result.firstFinderParticipantId == "user1")
        #expect(result.allFinderParticipantIds == ["user1"])
        #expect(result.summaryLabel == "Found by %@".localized("user1"))
    }

    @Test func summaryMultipleFindersOrderByDiscoveredAt() async throws {
        let base = Date()
        let d1 = makeDiscovery(participantId: "user2", discoveredAt: base.addingTimeInterval(10))
        let d2 = makeDiscovery(participantId: "user1", discoveredAt: base)
        let d3 = makeDiscovery(participantId: "user3", discoveredAt: base.addingTimeInterval(5))
        let result = ParticipantDiscoveryResolver.summary(discoveries: [d1, d2, d3], gameMode: .collaborative)
        #expect(result.firstFinderParticipantId == "user1")
        #expect(result.allFinderParticipantIds == ["user1", "user3", "user2"])
        #expect(result.summaryLabel == "%d finders".localized(3))
    }

    @Test func summaryTwoFindersLabel() async throws {
        let d1 = makeDiscovery(participantId: "alice")
        let d2 = makeDiscovery(participantId: "bob")
        let result = ParticipantDiscoveryResolver.summary(discoveries: [d1, d2], gameMode: .collaborative)
        #expect(result.allFinderParticipantIds.count == 2)
        #expect(result.summaryLabel == "%d finders".localized(2))
    }

    @Test func summarySingleFinderLabelFormat() async throws {
        let discovery = makeDiscovery(participantId: "alice")
        let result = ParticipantDiscoveryResolver.summary(discoveries: [discovery])
        #expect(result.summaryLabel == "Found by %@".localized("alice"))
    }

    @Test func summaryCompetitiveMultipleFindersEmphasizesFirstFinderInLabel() async throws {
        let base = Date()
        let d1 = makeDiscovery(participantId: "user1", discoveredAt: base)
        let d2 = makeDiscovery(participantId: "user2", discoveredAt: base.addingTimeInterval(1))
        let result = ParticipantDiscoveryResolver.summary(discoveries: [d1, d2], gameMode: .competitive)
        #expect(result.allFinderParticipantIds == ["user1", "user2"])
        #expect(result.summaryLabel == "Found by %@".localized("user1"))
    }
}
