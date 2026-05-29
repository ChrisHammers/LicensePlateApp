//
//  FriendsHubInviteFilter.swift
//  LicensePlateApp
//
//  Step 09 — pure invite splitting for Friends hub + unit tests.
//

import Foundation

enum FriendsHubInviteFilter {
    static func splitFriendInvites(_ invites: [Invite], userId: String) -> (incoming: [Invite], outgoing: [Invite]) {
        let friendInvites = invites.filter { invite in
            invite.typeEnum == .friend && invite.statusEnum == .pending
        }
        let incoming = friendInvites.filter { $0.toUserId == userId }
        let outgoing = friendInvites.filter { $0.fromUserId == userId }
        return (incoming, outgoing)
    }
}
