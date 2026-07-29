//
//  ParticipantDisplayName.swift
//  LicensePlateApp
//
//  Decorates a participant display name with a localized "[You]" suffix when the
//  participant is the signed-in user in a mixed current+peer list.
//

import Foundation

enum ParticipantDisplayName {
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
