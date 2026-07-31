//
//  XpDisplayedTotalResolver.swift
//  LicensePlateApp
//
//  Shared displayed XP for toast rank band snapshots (same as profile / celebrations).
//

import Foundation

@MainActor
enum XpDisplayedTotalResolver {

    static func totalXp(
        userId: String,
        xpLedger: XpLedgerRepositoryProtocol,
        remoteReader: XpGainToastRemoteReading
    ) -> Int {
        let events = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        var verified: Int?
        var hasGrantSnapshot = false
        if let remote = remoteReader as? XpGrantRemoteRepository {
            hasGrantSnapshot = remote.hasReceivedInitialSnapshot
            if hasGrantSnapshot {
                verified = remote.verifiedTotalXp
            }
        }
        return ProgressionDisplayTotalsResolver.resolve(
            userId: userId,
            ledgerEvents: events,
            serverSnapshot: UserProgressionRepository.shared.snapshot,
            verifiedGrantSum: verified,
            hasReceivedGrantSnapshot: hasGrantSnapshot
        ).displayedTotalXp
    }
}
