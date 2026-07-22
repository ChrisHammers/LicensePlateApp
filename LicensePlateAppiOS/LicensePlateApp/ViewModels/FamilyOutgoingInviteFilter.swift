//
//  FamilyOutgoingInviteFilter.swift
//  LicensePlateApp
//
//  Pure filter for family-scoped pending outgoing invites (member-visible).
//

import Foundation

enum FamilyOutgoingInviteFilter {
    /// Pending family invites for `familyId` (invitee has not responded yet).
    static func pendingOutgoing(from invites: [Invite], familyId: String) -> [Invite] {
        invites.filter { invite in
            invite.typeEnum == .family
                && invite.familyId == familyId
                && invite.statusEnum == .pending
                && invite.toUserId != nil
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Invitee user ids already covered by a pending family invite for this family.
    static func pendingInviteeIds(from invites: [Invite], familyId: String) -> Set<String> {
        Set(
            pendingOutgoing(from: invites, familyId: familyId)
                .compactMap(\.toUserId)
        )
    }
}
