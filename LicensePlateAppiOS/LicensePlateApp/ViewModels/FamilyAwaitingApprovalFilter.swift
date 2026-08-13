//
//  FamilyAwaitingApprovalFilter.swift
//  LicensePlateApp
//
//  Pure filter for requester-facing "accepted invite, awaiting captain approval".
//

import Foundation

enum FamilyAwaitingApprovalFilter {
    /// Accepted family invites for `userId` (newest first). Used when `activeFamilyId` is nil.
    ///
    /// `consumedInviteIds` excludes invites that were already redeemed into a real
    /// membership. The server leaves an approved invite in `accepted` forever (only the
    /// DECLINE path flips it), so after the member is removed the old invite would
    /// otherwise read as a live "waiting for approval" request that does not exist.
    static func awaitingApprovalInvites(
        from invites: [Invite],
        userId: String,
        consumedInviteIds: Set<String>
    ) -> [Invite] {
        invites.filter { invite in
            invite.typeEnum == .family
                && invite.toUserId == userId
                && invite.statusEnum == .accepted
                && invite.familyId != nil
                && !consumedInviteIds.contains(invite.inviteId)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Primary invite for the empty Family dashboard card.
    static func primaryAwaitingApprovalInvite(
        from invites: [Invite],
        userId: String,
        consumedInviteIds: Set<String>
    ) -> Invite? {
        awaitingApprovalInvites(
            from: invites,
            userId: userId,
            consumedInviteIds: consumedInviteIds
        ).first
    }
}
