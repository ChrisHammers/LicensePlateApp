//
//  LifetimeStatsRecomputeEngineTests.swift
//  LicensePlateAppTests
//
//  Deterministic lifetime stats: social classification, leaver exclusion, engine parity.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LifetimeStatsSocialClassificationTests {

    @Test func emptyFamilySet_isNeverFamilyOnly() {
        let roster = [
            TripParticipant(userId: "u1", role: .owner, joinedAt: .now),
            TripParticipant(userId: "u2", role: .member, joinedAt: .now)
        ]
        #expect(!LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: []))
    }

    @Test func soloParticipant_inFamily_isNotFamilyOnly() {
        let roster = [TripParticipant(userId: "u1", role: .owner, joinedAt: .now)]
        let family: Set<String> = ["u1", "u2"]
        #expect(!LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: family))
        #expect(
            LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: roster,
                subjectUserId: "u1",
                familyMemberUserIds: family,
                friendUserIds: []
            ) == .neither
        )
        #expect(!LifetimeStatsSocialClassification.isEntireFamilyTrip(activeParticipants: roster, familyMemberUserIds: family))
    }

    @Test func multiplayer_allInFamily_isFamilyOnly() {
        let roster = [
            TripParticipant(userId: "u1", role: .owner, joinedAt: .now),
            TripParticipant(userId: "u2", role: .member, joinedAt: .now)
        ]
        let family: Set<String> = ["u1", "u2"]
        #expect(LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: family))
        #expect(
            LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: roster,
                subjectUserId: "u1",
                familyMemberUserIds: family,
                friendUserIds: ["u2"]
            ) == .familyOnly
        )
    }

    @Test func multiplayer_strangerOnRoster_notFamilyOnly() {
        let roster = [
            TripParticipant(userId: "u1", role: .owner, joinedAt: .now),
            TripParticipant(userId: "outsider", role: .member, joinedAt: .now)
        ]
        let family: Set<String> = ["u1", "u2"]
        #expect(!LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: family))
    }

    @Test func leaverExcludedFromActiveRoster_soloRemaining_notFamilyOnly() {
        var leaver = TripParticipant(userId: "u2", role: .member, joinedAt: .now)
        leaver.leftAt = Date()
        let roster = [
            TripParticipant(userId: "u1", role: .owner, joinedAt: .now),
            leaver
        ]
        let family: Set<String> = ["u1", "u2"]
        let active = roster.filter { $0.leftAt == nil }
        #expect(!LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: active, familyMemberUserIds: family))
    }

    @Test func friendsOnly_whenAllPeersAreFriendsNotFamily() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "pal", role: .member, joinedAt: .now)
        ]
        #expect(
            LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: roster,
                subjectUserId: "me",
                familyMemberUserIds: ["me", "sis"],
                friendUserIds: ["pal"]
            ) == .friendsOnly
        )
    }

    @Test func mixed_whenFamilyPeerAndFriendNotFamilyPeer() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now),
            TripParticipant(userId: "pal", role: .member, joinedAt: .now)
        ]
        #expect(
            LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: roster,
                subjectUserId: "me",
                familyMemberUserIds: ["me", "sis"],
                friendUserIds: ["pal", "sis"]
            ) == .mixed
        )
    }

    @Test func dualOnlyRoster_isFamilyOnly_notMixed() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now)
        ]
        #expect(
            LifetimeStatsSocialClassification.classifySocialTrip(
                activeParticipants: roster,
                subjectUserId: "me",
                familyMemberUserIds: ["me", "sis"],
                friendUserIds: ["sis"]
            ) == .familyOnly
        )
    }

    @Test func entireFamily_whenAllFamilyOnRoster() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now)
        ]
        let family: Set<String> = ["me", "sis"]
        #expect(LifetimeStatsSocialClassification.isEntireFamilyTrip(activeParticipants: roster, familyMemberUserIds: family))
    }

    @Test func entireFamily_partialFamily_isFalse() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now)
        ]
        let family: Set<String> = ["me", "sis", "dad"]
        #expect(!LifetimeStatsSocialClassification.isEntireFamilyTrip(activeParticipants: roster, familyMemberUserIds: family))
        #expect(LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: family))
    }

    @Test func entireFamily_withOutsider_stillEntire() {
        let roster = [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now),
            TripParticipant(userId: "stranger", role: .member, joinedAt: .now)
        ]
        let family: Set<String> = ["me", "sis"]
        #expect(LifetimeStatsSocialClassification.isEntireFamilyTrip(activeParticipants: roster, familyMemberUserIds: family))
        #expect(!LifetimeStatsSocialClassification.isFamilyOnlyTrip(activeParticipants: roster, familyMemberUserIds: family))
    }

    @Test func relationshipLabel_dualIsFriendAndFamily() {
        #expect(SocialRelationshipLabel.localizedLabel(isFamily: true, isFriend: true) == "Friend & Family".localized)
        #expect(SocialRelationshipLabel.localizedLabel(isFamily: true, isFriend: false) == "Family".localized)
        #expect(SocialRelationshipLabel.localizedLabel(isFamily: false, isFriend: true) == "Friend".localized)
    }
}

struct LifetimeStatsRecomputeEnginePureTests {

    private func baseSessionSnapshot(
        id: UUID = UUID(),
        subject: String,
        participants: [TripParticipant],
        status: TripSessionState = .ended
    ) -> LifetimeStatsSessionSnapshot {
        LifetimeStatsSessionSnapshot(
            id: id,
            name: "Trip",
            statusRaw: status.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: subject,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_100),
            endedBy: subject,
            participants: participants,
            riskFlags: nil
        )
    }

    @Test func skipsTripWhenSubjectHasLeftAt() throws {
        var left = TripParticipant(userId: "me", role: .member, joinedAt: .now)
        left.leftAt = Date()
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "owner", role: .owner, joinedAt: .now),
            left
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: ["me", "owner"],
            friendUserIds: [],
            trips: [trip]
        )
        let out = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(out.totalCompletedTrips == 0)
        #expect(out.familyOnlyTripsCount == 0)
    }

    @Test func countsEndedTripForSubject() throws {
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now)
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: [],
            friendUserIds: [],
            trips: [trip]
        )
        let out = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(out.totalCompletedTrips == 1)
        #expect(out.totalGamesPlayed == 0)
        #expect(out.familyOnlyTripsCount == 0)
        #expect(out.entireFamilyTripsCount == 0)
    }

    @Test func familyOnlyTripCount_whenRosterSubsetOfFamily() throws {
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now)
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let family: Set<String> = ["me", "sis", "dad"]
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: family,
            friendUserIds: [],
            trips: [trip]
        )
        let out = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(out.totalCompletedTrips == 1)
        #expect(out.familyOnlyTripsCount == 1)
        #expect(out.entireFamilyTripsCount == 0)
    }

    @Test func entireAndFamilyOnly_whenExactFamilyRoster() throws {
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "sis", role: .member, joinedAt: .now)
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let family: Set<String> = ["me", "sis"]
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: family,
            friendUserIds: [],
            trips: [trip]
        )
        let out = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(out.familyOnlyTripsCount == 1)
        #expect(out.entireFamilyTripsCount == 1)
    }

    @Test func friendsOnlyTripCount() throws {
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now),
            TripParticipant(userId: "pal", role: .member, joinedAt: .now)
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: ["me"],
            friendUserIds: ["pal"],
            trips: [trip]
        )
        let out = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(out.friendsOnlyTripsCount == 1)
        #expect(out.familyOnlyTripsCount == 0)
    }

    @Test func computeIsDeterministicAsideFromTimestamp() throws {
        let session = baseSessionSnapshot(subject: "me", participants: [
            TripParticipant(userId: "me", role: .owner, joinedAt: .now)
        ])
        let trip = LifetimeStatsTripInput(session: session, games: [], discoveries: [])
        let input = LifetimeStatsRecomputeInput(
            subjectUserId: "me",
            familyMemberUserIds: [],
            friendUserIds: [],
            trips: [trip]
        )
        let a = try LifetimeStatsRecomputeEngine.compute(input)
        let b = try LifetimeStatsRecomputeEngine.compute(input)
        #expect(a.totalCompletedTrips == b.totalCompletedTrips)
        #expect(a.totalGamesPlayed == b.totalGamesPlayed)
        #expect(a.totalDiscoveries == b.totalDiscoveries)
        #expect(a.totalWeightedScore == b.totalWeightedScore)
        #expect(a.familyOnlyTripsCount == b.familyOnlyTripsCount)
        #expect(a.friendsOnlyTripsCount == b.friendsOnlyTripsCount)
        #expect(a.mixedFriendsFamilyTripsCount == b.mixedFriendsFamilyTripsCount)
        #expect(a.entireFamilyTripsCount == b.entireFamilyTripsCount)
    }
}
