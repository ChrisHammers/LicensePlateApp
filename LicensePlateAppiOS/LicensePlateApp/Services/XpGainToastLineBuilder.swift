//
//  XpGainToastLineBuilder.swift
//  LicensePlateApp
//
//  Eligibility rules for XP gain toast ingest (grouping lives in XpGainToastSourceMapper).
//

import Foundation

enum XpGainToastEligibility {

    static func shouldToastLedgerRow(_ row: XpLedgerEvent) -> Bool {
        row.xpDelta > 0
    }

    static func shouldToastRemoteGrant(_ grant: UserXpGrant) -> Bool {
        guard grant.amount > 0 else { return false }
        // Discovery and return-streak toast from local ledger (offline-first); skip remote re-toast.
        if grant.reason == UserXpGrantReason.regionFoundBaseDiscovery.rawValue { return false }
        if grant.reason == UserXpGrantReason.returnStreakDaily.rawValue { return false }
        return true
    }

    /// Identity of a single completion award, shared by the local ledger row and the server grant that
    /// later mirrors it. `XpReasonCode` raw values match `UserXpGrantReason`, and both sides carry the
    /// originating activity event id (`sourceEventId` locally, `sourceId` on the grant).
    ///
    /// Completion awards are matched per award rather than blanket-suppressed by reason (the rule used for
    /// discovery/return-streak) so a multiplayer peer, whose device never wrote the local row, still toasts
    /// when the grant arrives.
    static func localAwardKey(for row: XpLedgerEvent) -> String? {
        guard row.grantKind == .tripCompletion, !row.sourceEventId.isEmpty else { return nil }
        return "\(row.sourceEventId)|\(row.reasonCode.rawValue)"
    }

    static func localAwardKey(for grant: UserXpGrant) -> String {
        "\(grant.sourceId)|\(grant.reason)"
    }
}
