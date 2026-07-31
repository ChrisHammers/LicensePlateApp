//
//  ProgressionDisplayTotals.swift
//  LicensePlateApp
//
//  Single displayed XP projection: server progression + open provisional ledger rows
//  that are not yet listed in appliedProgressionEvents / appliedProgressionScopes.
//

import Foundation

struct ProgressionDisplayTotals: Equatable, Sendable {
    var serverXp: Int
    var openProvisionalXp: Int
    var displayedTotalXp: Int
    var isXpGrantLedgerVerified: Bool
    var verifiedGrantSum: Int?

    static let empty = ProgressionDisplayTotals(
        serverXp: 0,
        openProvisionalXp: 0,
        displayedTotalXp: 0,
        isXpGrantLedgerVerified: false,
        verifiedGrantSum: nil
    )
}

enum ProgressionDisplayTotalsResolver {

    /// Authoritative display total for profile, rank, toast band, and celebrations.
    static func resolve(
        userId: String,
        ledgerEvents: [XpLedgerEvent],
        serverSnapshot: UserProgressionSnapshot?,
        verifiedGrantSum: Int?,
        hasReceivedGrantSnapshot: Bool,
        now: Date = .now
    ) -> ProgressionDisplayTotals {
        let serverXp = max(0, serverSnapshot?.totalXp ?? 0)
        let appliedEventIds = serverSnapshot?.appliedProgressionEventIds ?? []
        let appliedScopes = serverSnapshot?.appliedProgressionScopeKeys ?? []
        let openProvisional = LedgerPendingXpTotals.openProvisionalSum(
            from: ledgerEvents,
            appliedProgressionEventIds: appliedEventIds,
            appliedProgressionScopeKeys: appliedScopes,
            now: now
        )
        let matches = hasReceivedGrantSnapshot
            && verifiedGrantSum != nil
            && verifiedGrantSum == serverXp
        let verified: Int? = {
            guard hasReceivedGrantSnapshot, let sum = verifiedGrantSum else { return nil }
            // Grants are audit-only; never replace a mismatched progression total.
            return matches || serverXp == 0 ? sum : nil
        }()
        return ProgressionDisplayTotals(
            serverXp: serverXp,
            openProvisionalXp: openProvisional,
            displayedTotalXp: max(0, serverXp + openProvisional),
            isXpGrantLedgerVerified: matches,
            verifiedGrantSum: verified
        )
    }
}
