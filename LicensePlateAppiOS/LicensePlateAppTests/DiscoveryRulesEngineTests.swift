//
//  DiscoveryRulesEngineTests.swift
//  LicensePlateAppTests
//
//  Step 03 — DiscoveryRulesEngine: evaluateDiscoverySubmission outcomes and creditsForDiscoveries.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoveryRulesEngineTests {

    private let gameInstanceId = UUID()

    private func makeDiscovery(
        participantId: String,
        targetId: String = "region-1",
        discoveredAt: Date = Date()
    ) -> GameDiscovery {
        GameDiscovery(
            gameInstanceId: gameInstanceId,
            participantId: participantId,
            targetId: targetId,
            discoveredAt: discoveredAt,
            inputMethod: .list
        )
    }

    // MARK: - evaluateDiscoverySubmission: no existing (new_credit)

    @Test func evaluateCompetitiveNoExistingReturnsNewCreditFull() async throws {
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [],
            candidateParticipantId: "user1",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .newCredit)
        #expect(result.shouldAppendEvent == true)
        #expect(result.creditsToAssign?.count == 1)
        #expect(result.creditsToAssign?[0].participantId == "user1")
        #expect(result.creditsToAssign?[0].creditType == .full)
    }

    @Test func evaluateCollaborativeNoExistingReturnsNewCredit() async throws {
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .collaborative,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [],
            candidateParticipantId: "user1",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .newCredit)
        #expect(result.shouldAppendEvent == true)
        #expect(result.creditsToAssign?.count == 1)
        #expect(result.creditsToAssign?[0].creditType == .shared)
    }

    // MARK: - evaluateDiscoverySubmission: same participant (personal_duplicate)

    @Test func evaluateCompetitiveSameParticipantReturnsPersonalDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [existing],
            candidateParticipantId: "user1",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .personalDuplicate)
        #expect(result.shouldAppendEvent == true)
        #expect(result.creditsToAssign == nil)
    }

    @Test func evaluateCollaborativeSameParticipantReturnsPersonalDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .collaborative,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [existing],
            candidateParticipantId: "user1",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .personalDuplicate)
        #expect(result.creditsToAssign == nil)
    }

    // MARK: - evaluateDiscoverySubmission: other participant

    @Test func evaluateCompetitiveOtherParticipantReturnsRejectedDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [existing],
            candidateParticipantId: "user2",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .rejectedDuplicate)
        #expect(result.shouldAppendEvent == false)
        #expect(result.creditsToAssign == nil)
    }

    @Test func evaluateCollaborativeOtherParticipantReturnsSharedDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .collaborative,
            tripMode: .multiplayer,
            existingDiscoveriesForTarget: [existing],
            candidateParticipantId: "user2",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .sharedDuplicate)
        #expect(result.shouldAppendEvent == true)
        #expect(result.creditsToAssign?.count == 2)
        let participantIds = Set(result.creditsToAssign!.map(\.participantId))
        #expect(participantIds == Set(["user1", "user2"]))
        for credit in result.creditsToAssign! {
            #expect(credit.creditType == .shared)
            #expect(credit.weight == 0.5)
        }
    }

    @Test func evaluateSoloTripOtherParticipantReturnsRejectedInvalidParticipantEvenWhenCollaborative() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .collaborative,
            tripMode: .solo,
            existingDiscoveriesForTarget: [existing],
            candidateParticipantId: "user2",
            candidateTargetId: "region-1",
            gameInstanceId: gameInstanceId,
            inputMethod: .list,
            occurredAt: Date()
        )
        #expect(result.outcome == .rejectedInvalidParticipant)
        #expect(result.shouldAppendEvent == false)
        #expect(result.creditsToAssign == nil)
    }

    // MARK: - creditsForDiscoveries

    @Test func creditsForDiscoveriesCompetitiveOneDiscoveryReturnsOneCredit() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let byTarget = ["region-1": [discovery]]
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .competitive, discoveriesByTarget: byTarget)
        #expect(credits.count == 1)
        #expect(credits[0].participantId == "user1")
        #expect(credits[0].creditType == .full)
    }

    @Test func creditsForDiscoveriesCollaborativeTwoFindersReturnsTwoSharedCredits() async throws {
        let d1 = makeDiscovery(participantId: "user1", discoveredAt: Date().addingTimeInterval(-1))
        let d2 = makeDiscovery(participantId: "user2", discoveredAt: Date())
        let byTarget = ["region-1": [d1, d2]]
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .collaborative, discoveriesByTarget: byTarget)
        #expect(credits.count == 2)
        let participantIds = Set(credits.map(\.participantId))
        #expect(participantIds == Set(["user1", "user2"]))
        for credit in credits {
            #expect(credit.creditType == .shared)
            #expect(credit.weight == 0.5)
        }
    }

    @Test func creditsForDiscoveriesCompetitiveTwoFindersReturnsFirstFinderCreditOnly() async throws {
        let d1 = makeDiscovery(participantId: "user1", discoveredAt: Date().addingTimeInterval(-1))
        let d2 = makeDiscovery(participantId: "user2", discoveredAt: Date())
        let byTarget = ["region-1": [d1, d2]]
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .competitive, discoveriesByTarget: byTarget)
        #expect(credits.count == 1)
        #expect(credits[0].participantId == "user1")
        #expect(credits[0].creditType == .full)
    }

    @Test func creditsForDiscoveriesEmptyTargetsReturnsEmpty() async throws {
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .competitive, discoveriesByTarget: [:])
        #expect(credits.isEmpty)
    }
}
