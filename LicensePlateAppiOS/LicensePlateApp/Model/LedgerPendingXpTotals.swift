//
//  LedgerPendingXpTotals.swift
//  LicensePlateApp
//
//  Pure read model: provisional XP still open on the local ledger (not server progression).
//

import Foundation

struct LedgerPendingXpTotals: Equatable, Sendable {
    var provisionalSum: Int
    var lastRecomputedAt: Date

    static func fromLedgerEvents(_ events: [XpLedgerEvent], now: Date = .now) -> LedgerPendingXpTotals {
        let sum = events.filter { $0.status == .provisional }.reduce(0) { $0 + $1.xpDelta }
        return LedgerPendingXpTotals(provisionalSum: sum, lastRecomputedAt: now)
    }
}
