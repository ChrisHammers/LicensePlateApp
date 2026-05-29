//
//  TripParticipantRankingTests.swift
//  LicensePlateAppTests
//
//  Step 11 — TripParticipantRanking and TripRosterContributionMerge.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripParticipantRankingTests {

    @Test func mergeAddsRosterMembersWithZeroContributions() {
        let roster = [
            TripParticipant(userId: "a", role: .owner),
            TripParticipant(userId: "b", role: .member)
        ]
        let contributions = [
            ParticipantContribution(participantId: "a", discoveryCount: 3, weightedScore: 3, firstFindCount: 2)
        ]
        let merged = TripRosterContributionMerge.merge(roster: roster, contributions: contributions)
        #expect(merged.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: merged.map { ($0.participantId, $0) })
        #expect(byId["a"]?.weightedScore == 3)
        #expect(byId["b"]?.weightedScore == 0)
        #expect(byId["b"]?.discoveryCount == 0)
    }

    @Test func rankCompetitionOrder122() {
        let items = [
            ParticipantContribution(participantId: "z", discoveryCount: 2, weightedScore: 10, firstFindCount: 2),
            ParticipantContribution(participantId: "y", discoveryCount: 2, weightedScore: 10, firstFindCount: 1),
            ParticipantContribution(participantId: "x", discoveryCount: 1, weightedScore: 8, firstFindCount: 1)
        ]
        let ranked = TripParticipantRanking.rankContributions(items)
        #expect(ranked.count == 3)
        #expect(ranked[0].rank == 1)
        #expect(ranked[0].contribution.participantId == "z")
        #expect(ranked[1].rank == 1)
        #expect(ranked[1].contribution.participantId == "y")
        #expect(ranked[2].rank == 3)
        #expect(ranked[0].isTiedOnScore == true)
        #expect(ranked[1].isTiedOnScore == true)
        #expect(ranked[2].isTiedOnScore == false)
    }

    @Test func rankSameScoreOrdersByFirstFindThenDiscoveryThenId() {
        let items = [
            ParticipantContribution(participantId: "bob", discoveryCount: 2, weightedScore: 5, firstFindCount: 1),
            ParticipantContribution(participantId: "alice", discoveryCount: 2, weightedScore: 5, firstFindCount: 2)
        ]
        let ranked = TripParticipantRanking.rankContributions(items)
        #expect(ranked[0].contribution.participantId == "alice")
        #expect(ranked[1].contribution.participantId == "bob")
        #expect(ranked[0].rank == 1)
        #expect(ranked[1].rank == 1)
    }
}
