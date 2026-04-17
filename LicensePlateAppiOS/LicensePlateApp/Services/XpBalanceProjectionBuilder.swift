//
//  XpBalanceProjectionBuilder.swift
//  LicensePlateApp
//
//  Folds append-only ledger rows into a balance read model.
//

import Foundation

enum XpBalanceProjectionBuilder {

    /// Builds a balance for one user in one game instance from already-scoped ledger events.
    static func build(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        ledgerEvents: [XpLedgerEvent],
        now: Date = .now
    ) -> XpBalanceProjection {
        let scoped = ledgerEvents.filter {
            $0.userId == userId && $0.sessionId == sessionId && $0.gameInstanceId == gameInstanceId
        }
        let provisionalSum = scoped.filter { $0.status == .provisional }.reduce(0) { $0 + $1.xpDelta }
        let provisionalRowCount = scoped.filter { $0.status == .provisional }.count
        let netAllStatuses = scoped.reduce(0) { $0 + $1.xpDelta }
        return XpBalanceProjection(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            totalXpFinal: netAllStatuses,
            totalXpProvisional: provisionalSum,
            displayXp: netAllStatuses,
            pendingAdjustmentCount: provisionalRowCount,
            lastRecomputedAt: now
        )
    }
}
