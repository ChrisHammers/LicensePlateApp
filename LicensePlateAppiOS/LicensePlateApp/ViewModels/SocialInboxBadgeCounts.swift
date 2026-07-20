//
//  SocialInboxBadgeCounts.swift
//  LicensePlateApp
//
//  Pure pending friend/family invite + captain approval counts for home + settings badges.
//  Semantics match FriendsHub / FamilyDashboard (incoming pending only; approvals for managers).
//

import Foundation

enum SocialInboxBadgeCounts {
    struct Counts: Equatable {
        var friend: Int
        var family: Int
        var familyApprovals: Int

        var familyInbox: Int { family + familyApprovals }
        var total: Int { friend + family + familyApprovals }
    }

    static func counts(
        from invites: [Invite],
        userId: String,
        pendingRequestsByFamily: [String: [PendingJoinRequest]] = [:],
        membersByFamily: [String: [FamilyMember]] = [:],
        activeFamilyId: String? = nil
    ) -> Counts {
        let friend = FriendsHubInviteFilter.splitFriendInvites(invites, userId: userId).incoming.count
        let family = invites.filter { invite in
            invite.typeEnum == .family
                && invite.toUserId == userId
                && invite.statusEnum == .pending
        }.count
        let familyApprovals = pendingFamilyApprovalsCount(
            pendingRequestsByFamily: pendingRequestsByFamily,
            membersByFamily: membersByFamily,
            userId: userId,
            activeFamilyId: activeFamilyId
        )
        return Counts(friend: friend, family: family, familyApprovals: familyApprovals)
    }

    /// Pending join requests the current user must approve (creator/captain only).
    static func pendingFamilyApprovalsCount(
        pendingRequestsByFamily: [String: [PendingJoinRequest]],
        membersByFamily: [String: [FamilyMember]],
        userId: String,
        activeFamilyId: String?
    ) -> Int {
        guard let familyId = activeFamilyId,
              let members = membersByFamily[familyId],
              let me = members.first(where: { $0.userId == userId }),
              me.isCaptainOrCreator else {
            return 0
        }
        let requests = pendingRequestsByFamily[familyId] ?? []
        return requests.filter { $0.statusEnum == .pending }.count
    }
}
