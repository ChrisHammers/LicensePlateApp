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

    @Test func evaluateSoloNoExistingReturnsNewCredit() async throws {
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .solo,
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

    @Test func evaluateCompetitiveNoExistingReturnsNewCredit() async throws {
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
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
    }

    // MARK: - evaluateDiscoverySubmission: same participant (personal_duplicate)

    @Test func evaluateSoloSameParticipantReturnsPersonalDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .solo,
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

    @Test func evaluateCompetitiveSameParticipantReturnsPersonalDuplicate() async throws {
        let existing = makeDiscovery(participantId: "user1")
        let result = DiscoveryRulesEngine.evaluateDiscoverySubmission(
            mode: .competitive,
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

    // MARK: - creditsForDiscoveries

    @Test func creditsForDiscoveriesSoloOneDiscoveryReturnsOneCredit() async throws {
        let discovery = makeDiscovery(participantId: "user1")
        let byTarget = ["region-1": [discovery]]
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .solo, discoveriesByTarget: byTarget)
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
        let credits = DiscoveryRulesEngine.creditsForDiscoveries(mode: .solo, discoveriesByTarget: [:])
        #expect(credits.isEmpty)
    }
}
