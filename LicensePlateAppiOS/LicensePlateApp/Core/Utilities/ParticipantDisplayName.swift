//
//  ParticipantDisplayName.swift
//  LicensePlateApp
//
//  Decorates a participant display name with a localized "[You]" suffix when the
//  participant is the signed-in user in a mixed current+peer list.
//

import Foundation

enum ParticipantDisplayName {
    /// Mirrors the server's `DELETED_USER_TOMBSTONE_PREFIX`
    /// (`functions/src/accountDeletionDeidentifyCore.ts`): a deleted account's residue in
    /// shared trip data is re-keyed to `deleted-user-<hash>` (FR-50 de-identification).
    static let deletedUserTombstonePrefix = "deleted-user"

    /// The in-app label for a participant no display name resolved for. A raw participant
    /// id must never reach the screen — it is either a Firebase uid or a deletion
    /// tombstone. Owner-found 2026-09-07: a deleted co-player rendered as
    /// "deleted-user-xyz" on every other player's roster. FR-100 closed this for the
    /// export card only; this is the in-app twin, and it deliberately says nothing
    /// about WHY a living participant is unresolved (an unreadable profile is usually
    /// a child's).
    static func unresolvedLabel(for participantId: String) -> String {
        if participantId.hasPrefix(deletedUserTombstonePrefix) {
            return "participant.former_player".localized
        }
        return "participant.unknown_player".localized
    }

    /// `displayName` when present and non-empty, else the neutral in-app fallback.
    static func resolved(_ displayName: String?, participantId: String) -> String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return unresolvedLabel(for: participantId)
    }

    /// Returns `displayName` unchanged unless `userId` matches `currentUserId`, in which
    /// case appends the localized `[You]` marker (e.g. `"Alex [You]"`).
    static func decorated(_ displayName: String, userId: String, currentUserId: String?) -> String {
        guard let currentUserId, !currentUserId.isEmpty, userId == currentUserId else {
            return displayName
        }
        return decorateCurrentUser(displayName)
    }

    /// Decorates when the caller already knows the row represents the signed-in user.
    static func decorated(_ displayName: String, isCurrentUser: Bool) -> String {
        guard isCurrentUser else { return displayName }
        return decorateCurrentUser(displayName)
    }

    private static func decorateCurrentUser(_ displayName: String) -> String {
        "%@ [You]".localized(displayName)
    }
}
