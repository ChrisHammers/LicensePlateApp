//
//  GameCreditCalculatorTests.swift
//  LicensePlateAppTests
//
//  Step 05 — GameCreditCalculator: credits for collaborative vs competitive/solo.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameCreditCalculatorTests {

    private func makeDiscovery(
        id: String = UUID().uuidString,
        participantId: String,
        targetId: String = "region-1",
        gameInstanceId: UUID = UUID()
    ) -> GameDiscovery {
        GameDiscovery(
            id: id,
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: Date(),
            inputMethod: .list
        )
    }

    @Test func creditsSoloOneFullCreditForDiscoverer() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = GameCreditCalculator.credits(
            for: .solo,
            discovery: discovery,
            existingDiscoveriesForTarget: []
        )
        #expect(result.count == 1)
        #expect(result[0].participantId == "user1")
        #expect(result[0].creditType == .full)
        #expect(result[0].discoveryId == discovery.id)
        #expect(result[0].weight == 1.0)
    }

    @Test func creditsCompetitiveOneFullCreditForDiscoverer() async throws {
        let discovery = makeDiscovery(participantId: "user2")
        let result = GameCreditCalculator.credits(
            for: .competitive,
            discovery: discovery,
            existingDiscoveriesForTarget: []
        )
        #expect(result.count == 1)
        #expect(result[0].participantId == "user2")
        #expect(result[0].creditType == .full)
        #expect(result[0].weight == 1.0)
    }

    @Test func creditsCollaborativeSingleFinderOneSharedCredit() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = GameCreditCalculator.credits(
            for: .collaborative,
            discovery: discovery,
            existingDiscoveriesForTarget: []
        )
        #expect(result.count == 1)
        #expect(result[0].participantId == "user1")
        #expect(result[0].creditType == .shared)
        #expect(result[0].weight == 1.0)
    }

    @Test func creditsCollaborativeTwoFindersTwoSharedCreditsWithHalfWeight() async throws {
        let existing = makeDiscovery(participantId: "user1", targetId: "region-1")
        let newDiscovery = makeDiscovery(participantId: "user2", targetId: "region-1")
        let result = GameCreditCalculator.credits(
            for: .collaborative,
            discovery: newDiscovery,
            existingDiscoveriesForTarget: [existing]
        )
        #expect(result.count == 2)
        let participantIds = Set(result.map(\.participantId))
        #expect(participantIds == Set(["user1", "user2"]))
        for credit in result {
            #expect(credit.creditType == .shared)
            #expect(credit.discoveryId == newDiscovery.id)
            #expect(credit.weight == 0.5)
        }
    }

    @Test func creditsCollaborativeThreeFindersWeightsOneThird() async throws {
        let existing1 = makeDiscovery(participantId: "user1", targetId: "region-1")
        let existing2 = makeDiscovery(participantId: "user2", targetId: "region-1")
        let newDiscovery = makeDiscovery(participantId: "user3", targetId: "region-1")
        let result = GameCreditCalculator.credits(
            for: .collaborative,
            discovery: newDiscovery,
            existingDiscoveriesForTarget: [existing1, existing2]
        )
        #expect(result.count == 3)
        let participantIds = Set(result.map(\.participantId))
        #expect(participantIds == Set(["user1", "user2", "user3"]))
        for credit in result {
            #expect(credit.creditType == .shared)
            #expect(credit.weight == 1.0 / 3.0)
        }
    }

    @Test func creditsCombinedOneFullCreditForDiscoverer() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let result = GameCreditCalculator.credits(
            for: .combined,
            discovery: discovery,
            existingDiscoveriesForTarget: []
        )
        #expect(result.count == 1)
        #expect(result[0].creditType == .full)
        #expect(result[0].participantId == "user1")
    }

    // Step 06.5.5 — competitive: only first finder receives credit when passing first discovery
    @Test func creditsCompetitiveTwoFindersSameTargetOnlyFirstGetsCreditWhenPassingFirst() async throws {
        let first = makeDiscovery(participantId: "user1", targetId: "region-1")
        let second = makeDiscovery(participantId: "user2", targetId: "region-1")
        let result = GameCreditCalculator.credits(
            for: .competitive,
            discovery: first,
            existingDiscoveriesForTarget: [second]
        )
        #expect(result.count == 1)
        #expect(result[0].participantId == "user1")
        #expect(result[0].creditType == .full)
        #expect(result[0].weight == 1.0)
    }
}
