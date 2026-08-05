//
//  LedgerPendingXpTotals.swift
//  LicensePlateApp
//
//  Pure read model: open provisional XP still pending cloud confirmation,
//  plus locally confirmed finals that are not yet reflected in server progression.
//

import Foundation

struct LedgerPendingXpTotals: Equatable, Sendable {
    var provisionalSum: Int
    var lastRecomputedAt: Date

    /// All provisional rows (legacy callers). Prefer `openProvisionalSum` when server applied ids are known.
    static func fromLedgerEvents(_ events: [XpLedgerEvent], now: Date = .now) -> LedgerPendingXpTotals {
        let sum = events
            .filter { $0.status == .provisional }
            .reduce(0) { $0 + $1.xpDelta }
        return LedgerPendingXpTotals(provisionalSum: sum, lastRecomputedAt: now)
    }

    /// XP that should still inflate the displayed total above the server snapshot.
    /// Includes open provisional rows, final discovery mirrors not yet listed in applied events,
    /// and return-streak daily finals not yet listed in applied progression scopes.
    static func openProvisionalSum(
        from events: [XpLedgerEvent],
        appliedProgressionEventIds: Set<String>,
        appliedProgressionScopeKeys: Set<String> = [],
        now: Date = .now
    ) -> Int {
        _ = now
        return events.reduce(0) { partial, row in
            guard row.xpDelta != 0 else { return partial }
            if isServerApplied(
                row,
                appliedProgressionEventIds: appliedProgressionEventIds,
                appliedProgressionScopeKeys: appliedProgressionScopeKeys
            ) {
                return partial
            }
            switch row.status {
            case .provisional:
                return partial + row.xpDelta
            case .final where row.grantKind == .finalDiscoveryAward:
                // Bridge the gap between sync confirmation and Firestore progression snapshot.
                return partial + row.xpDelta
            case .final
                where row.grantKind == .milestoneUnlock
                && row.reasonCode == .returnStreakDaily:
                return partial + row.xpDelta
            case .final, .voided:
                return partial
            }
        }
    }

    static func openProvisional(
        from events: [XpLedgerEvent],
        appliedProgressionEventIds: Set<String>,
        appliedProgressionScopeKeys: Set<String> = [],
        now: Date = .now
    ) -> LedgerPendingXpTotals {
        LedgerPendingXpTotals(
            provisionalSum: openProvisionalSum(
                from: events,
                appliedProgressionEventIds: appliedProgressionEventIds,
                appliedProgressionScopeKeys: appliedProgressionScopeKeys,
                now: now
            ),
            lastRecomputedAt: now
        )
    }

    private static func isServerApplied(
        _ row: XpLedgerEvent,
        appliedProgressionEventIds: Set<String>,
        appliedProgressionScopeKeys: Set<String>
    ) -> Bool {
        if appliedProgressionEventIds.contains(row.sourceEventId) {
            return true
        }
        if let original = row.metadata?[XpLedgerMetadataKey.originalDiscoveryEventId],
           appliedProgressionEventIds.contains(original) {
            return true
        }
        if row.reasonCode == .returnStreakDaily {
            let scopeKey = ReturnStreakXpScopeKey.daily(userId: row.userId, dayKey: row.itemId)
            if appliedProgressionScopeKeys.contains(scopeKey) {
                return true
            }
        }
        return false
    }
}
