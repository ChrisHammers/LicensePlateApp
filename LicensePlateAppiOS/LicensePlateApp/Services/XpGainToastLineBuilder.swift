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
}
