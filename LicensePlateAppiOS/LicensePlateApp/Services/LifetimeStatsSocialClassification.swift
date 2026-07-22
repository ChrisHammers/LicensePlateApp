//
//  LifetimeStatsSocialClassification.swift
//  LicensePlateApp
//
//  Lifetime social-trip buckets + entire-family flag. Parity: functions/src/publicLifetimeStatsCore.ts
//

import Foundation

/// Mutually exclusive social trip classification for lifetime stats.
enum LifetimeStatsSocialTripBucket: String, Sendable, Equatable {
    case familyOnly
    case friendsOnly
    case mixed
    case neither
}

/// Family / friends trip rules for lifetime stats. Shared with unit tests.
enum LifetimeStatsSocialClassification: Sendable {

    /// Active roster ⊆ family, and at least two people still on the trip.
    static func isFamilyOnlyTrip(activeParticipants: [TripParticipant], familyMemberUserIds: Set<String>) -> Bool {
        isFamilyOnlyTrip(
            activeUserIds: activeParticipants.map(\.userId),
            familyMemberUserIds: familyMemberUserIds
        )
    }

    static func isFamilyOnlyTrip(activeUserIds: [String], familyMemberUserIds: Set<String>) -> Bool {
        guard familyMemberUserIds.isEmpty == false else { return false }
        guard activeUserIds.count >= 2 else { return false }
        return activeUserIds.allSatisfy { familyMemberUserIds.contains($0) }
    }

    /// Every active family member is still on the trip (`|F| >= 2` ∧ `F ⊆ R`).
    static func isEntireFamilyTrip(activeParticipants: [TripParticipant], familyMemberUserIds: Set<String>) -> Bool {
        isEntireFamilyTrip(
            activeUserIds: activeParticipants.map(\.userId),
            familyMemberUserIds: familyMemberUserIds
        )
    }

    static func isEntireFamilyTrip(activeUserIds: [String], familyMemberUserIds: Set<String>) -> Bool {
        guard familyMemberUserIds.count >= 2 else { return false }
        let roster = Set(activeUserIds)
        return familyMemberUserIds.isSubset(of: roster)
    }

    /// Family-wins for peers who are both family and friend (`Friends \ F`).
    static func classifySocialTrip(
        activeParticipants: [TripParticipant],
        subjectUserId: String,
        familyMemberUserIds: Set<String>,
        friendUserIds: Set<String>
    ) -> LifetimeStatsSocialTripBucket {
        classifySocialTrip(
            activeUserIds: activeParticipants.map(\.userId),
            subjectUserId: subjectUserId,
            familyMemberUserIds: familyMemberUserIds,
            friendUserIds: friendUserIds
        )
    }

    static func classifySocialTrip(
        activeUserIds: [String],
        subjectUserId: String,
        familyMemberUserIds: Set<String>,
        friendUserIds: Set<String>
    ) -> LifetimeStatsSocialTripBucket {
        guard activeUserIds.count >= 2 else { return .neither }

        if isFamilyOnlyTrip(activeUserIds: activeUserIds, familyMemberUserIds: familyMemberUserIds) {
            return .familyOnly
        }

        let effectiveFriends = friendUserIds.subtracting(familyMemberUserIds)
        let peers = activeUserIds.filter { $0 != subjectUserId }
        let famPeers = peers.filter { familyMemberUserIds.contains($0) }
        let friendPeers = peers.filter { effectiveFriends.contains($0) }

        if famPeers.isEmpty == false && friendPeers.isEmpty == false {
            return .mixed
        }

        if peers.isEmpty == false && peers.allSatisfy({ effectiveFriends.contains($0) }) {
            return .friendsOnly
        }

        return .neither
    }
}

/// Backward-compatible name used by older call sites / tests.
typealias LifetimeStatsFamilyClassification = LifetimeStatsSocialClassification
