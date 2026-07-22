//
//  FamilyAwaitingApprovalFilter.swift
//  LicensePlateApp
//
//  Pure filter for requester-facing "accepted invite, awaiting captain approval".
//

import Foundation

enum FamilyAwaitingApprovalFilter {
    /// Accepted family invites for `userId` (newest first). Used when `activeFamilyId` is nil.
    static func awaitingApprovalInvites(from invites: [Invite], userId: String) -> [Invite] {
        invites.filter { invite in
            invite.typeEnum == .family
                && invite.toUserId == userId
                && invite.statusEnum == .accepted
                && invite.familyId != nil
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Primary invite for the empty Family dashboard card.
    static func primaryAwaitingApprovalInvite(from invites: [Invite], userId: String) -> Invite? {
        awaitingApprovalInvites(from: invites, userId: userId).first
    }
}
