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
        // §3.1.1 item 12: a migration seal is bookkeeping, not a gain. `reconcileXpGrantLedger`
        // writes ONE row with `sourceType: "migration"` whose amount is `max(0, totalXp - sum(grants))`
        // (functions/src/reconcileXpGrantLedgerCore.ts, legacyUnledgeredGrantWrite /
        // computeLegacyUnledgeredDelta). `legacy_unledgered_balance` matches no group's `grantReasons`
        // in Resources/ProgressionCatalog.v1.json, so XpGainToastSourceMapper.matchGroup falls through
        // to the catch-all "other" group and it renders as exactly ONE line carrying the whole
        // pre-ledger balance — the owner-reported artefact. It is written AFTER the grants listener
        // binds, so the server-snapshot watermark structurally cannot stop it; this exclusion is
        // independently necessary. XP totals are untouched: XpDisplayedTotalResolver still counts the
        // grant in `verifiedTotalXp`; only the notification stops.
        if grant.reason == UserXpGrantReason.legacyUnledgeredBalance.rawValue { return false }
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

    // MARK: - §3.1.1 item 14 — the server award scope a local row mirrors

    /// The SERVER award scope string this local ledger row mirrors, or `nil` when the row has no
    /// server counterpart to join against — see `Model/XpServerScopeKey.swift` for the derivation
    /// and the byte-for-byte correspondence with `functions/src/progressionCore.ts`.
    ///
    /// The derivation moved to Model in §3.1.1 item 17, where `LedgerPendingXpTotals` began joining
    /// on the same strings to retire ledger rows the server has already paid. ONE implementation:
    /// a toast that suppresses on a scope and a total that retires on it must never disagree.
    static func mirroredServerScopeKey(for row: XpLedgerEvent) -> String? {
        XpServerScopeKey.mirrored(for: row)
    }
}
