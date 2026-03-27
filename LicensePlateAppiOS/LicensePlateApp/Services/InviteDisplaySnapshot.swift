//
//  InviteDisplaySnapshot.swift
//  LicensePlateApp
//
//  Step 6.9.6 Phase D — Trip vs game separation for invite rows (game count vs trip metadata).
//  Step 6.10 — Trip participation is derived from roster; not shown on invite rows.
//  Step 12.5 — Counterparty display names (never raw UIDs in UI).
//

import Foundation

/// Display strings for a trip invite row. Built from `TripInvite` plus optional local game count.
struct InviteDisplaySnapshot: Equatable, Sendable {
    let inviteId: String
    let tripName: String
    /// Game-scoped: shown only when `localGameCount` was supplied (local store query succeeded).
    let gamesOnTripLine: String?
    /// Incoming: "From: …"; outgoing: "To: …" with resolved display name.
    let counterpartyLine: String
    let statusLine: String

    /// - Parameters:
    ///   - localGameCount: Pass `nil` when the local game count is unknown.
    ///   - counterpartyDisplayName: Resolved name for inviter (incoming) or invitee (outgoing).
    ///   - isIncoming: `true` for invites addressed to the current user.
    static func make(
        from invite: TripInvite,
        localGameCount: Int?,
        counterpartyDisplayName: String? = nil,
        isIncoming: Bool = true
    ) -> InviteDisplaySnapshot {
        let gamesLine: String?
        if let count = localGameCount {
            gamesLine = count == 1 ? "1 game".localized : "%d games".localized(count)
        } else {
            gamesLine = nil
        }

        let name = counterpartyDisplayName ?? "Unknown user".localized
        let counterpartyLine: String = isIncoming
            ? "From: %@".localized(name)
            : "To: %@".localized(name)

        return InviteDisplaySnapshot(
            inviteId: invite.inviteId,
            tripName: invite.tripName,
            gamesOnTripLine: gamesLine,
            counterpartyLine: counterpartyLine,
            statusLine: "Status: %@".localized(invite.statusEnum.rawValue.capitalized)
        )
    }
}
