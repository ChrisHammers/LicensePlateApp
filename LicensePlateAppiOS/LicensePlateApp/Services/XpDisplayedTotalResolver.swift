//
//  XpDisplayedTotalResolver.swift
//  LicensePlateApp
//
//  Mirrors `XpProgressViewModel.displayedTotalXp` for toast rank band snapshots.
//

import Foundation

@MainActor
enum XpDisplayedTotalResolver {

    static func totalXp(
        userId: String,
        xpLedger: XpLedgerRepositoryProtocol,
        remoteReader: XpGainToastRemoteReading
    ) -> Int {
        let server = UserProgressionRepository.shared.snapshot?.totalXp ?? 0
        var verified: Int?
        if let remote = remoteReader as? XpGrantRemoteRepository,
           remote.hasReceivedInitialSnapshot {
            let value = remote.verifiedTotalXp
            verified = value > 0 || server == 0 ? value : nil
        }
        let base = verified ?? server
        let events = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        let pending = LedgerPendingXpTotals.fromLedgerEvents(events).provisionalSum
        return max(0, base + pending)
    }
}
