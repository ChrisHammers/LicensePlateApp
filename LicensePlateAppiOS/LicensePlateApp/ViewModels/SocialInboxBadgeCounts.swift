//
//  SocialInboxBadgeCounts.swift
//  LicensePlateApp
//
//  Pure pending friend/family invite counts for home + settings badges.
//  Semantics match FriendsHub / FamilyDashboard (incoming pending only).
//

import Foundation

enum SocialInboxBadgeCounts {
    struct Counts: Equatable {
        var friend: Int
        var family: Int

        var total: Int { friend + family }
    }

    static func counts(from invites: [Invite], userId: String) -> Counts {
        let friend = FriendsHubInviteFilter.splitFriendInvites(invites, userId: userId).incoming.count // Only incoming.
        let family = invites.filter { invite in
            invite.typeEnum == .family
                && invite.toUserId == userId
                && invite.statusEnum == .pending
        }.count
        return Counts(friend: friend, family: family)
    }
}
