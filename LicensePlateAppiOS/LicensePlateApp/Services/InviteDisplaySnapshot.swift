//
//  InviteDisplaySnapshot.swift
//  LicensePlateApp
//
//  Step 6.9.6 Phase D — Trip vs game separation for invite rows (game count vs trip metadata).
//  Step 6.10 — Trip participation is derived from roster; not shown on invite rows.
//

import Foundation

/// Display strings for a trip invite row. Built from `TripInvite` plus optional local game count.
struct InviteDisplaySnapshot: Equatable, Sendable {
    let inviteId: String
    let tripName: String
    /// Game-scoped: shown only when `localGameCount` was supplied (local store query succeeded).
    let gamesOnTripLine: String?
    let inviterLine: String
    let statusLine: String

    /// - Parameter localGameCount: Pass `nil` when the local game count is unknown (e.g. query failed or session not in store).
    static func make(from invite: TripInvite, localGameCount: Int?) -> InviteDisplaySnapshot {
        let gamesLine: String?
        if let count = localGameCount {
            gamesLine = count == 1 ? "1 game".localized : "%d games".localized(count)
        } else {
            gamesLine = nil
        }

        return InviteDisplaySnapshot(
            inviteId: invite.inviteId,
            tripName: invite.tripName,
            gamesOnTripLine: gamesLine,
            inviterLine: "Inviter: %@".localized(invite.fromUserId),
            statusLine: "Status: %@".localized(invite.statusEnum.rawValue.capitalized)
        )
    }
}
