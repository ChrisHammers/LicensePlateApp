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

    /// A row is retired when the SERVER total already contains the same award.
    ///
    /// Four joins, in order of directness:
    ///
    /// 1. **The event id.** The normal path: the server stamps `appliedProgressionEvents[eventId]`
    ///    in the same transaction that increments `totalXp`
    ///    (`functions/src/progressionOnActivityEvent.ts:118-178`).
    ///
    /// 2. **The server-rejection form of the event id** (§3.1.1 items 17 and 24). When the server
    ///    rejects this device's find — a competitive find that loses to an earlier one, or a find on
    ///    a trip the server reads as solo while a partner who has left holds the plate — its
    ///    `region_found` is never written remotely at all: `gameplayEventResolver` writes
    ///    `srvrej_<clientEventId>` instead, and progression grants base + `lifetime_unique_region` +
    ///    `first_find_of_day` off THAT document (`functions/src/progressionCore.ts`,
    ///    `rejectionPaysFind`). `appliedProgressionEvents` therefore only ever holds the `srvrej_`
    ///    id, while the local rows — the final discovery award plus the two provisional bonuses —
    ///    carry the client id that `SyncCoordinator` has already deleted the event for. Without this
    ///    join they never retire and inflate the displayed total by the whole find, permanently.
    ///
    ///    Invariant this join relies on: progression pays every `srvrej_` rejection the callable
    ///    returns for this device's own find (late competitive, invalid participant), so the rows
    ///    retire in the same snapshot that the payment lands in `totalXp`.
    ///
    /// 3. **The mirrored server award scope** (`XpServerScopeKey.mirrored(for:)`). Id-independent:
    ///    an applied scope means that award's amount is inside `totalXp`, whichever event paid it —
    ///    so it also covers a once-per-lifetime or once-per-day bonus the account earned on another
    ///    device, which the server will never grant this device a second time.
    ///    It covers the COMPLETION awards too (`game_ended`, `game_full_clear`, `trip_ended`): those
    ///    rows are provisional, and their scope being applied means another event — a peer's, or this
    ///    account's other device — already paid that award.
    ///
    /// 4. **The base discovery award's server scope** (`XpServerScopeKey.baseDiscoveryTotalOnlyScope(for:)`,
    ///    §3.1.1 item 29a). The same id-independent reasoning as join 3, for the one award join 3
    ///    leaves out: the same account finding the same plate in the same game on two devices. The
    ///    server pays base once under `xp_scope|…|base_region_discovery`, off whichever device's event
    ///    lands first, so the other device's base row must retire on that scope rather than wait for
    ///    its own event's no-increment stamp. Kept out of `mirrored(for:)` because that string is also
    ///    the toast's dedup key, and the toast rules for base discovery are not changed here.
    ///
    /// Join 2 is what makes the retirement robust to §3.1.1 item 18 (the server bills a rejected
    /// find's `first_find_of_day` under the UTC day of the rejection, not the device's day, so the
    /// scope in join 3 can legitimately disagree with the local row's). The `srvrej_` id carries no
    /// day, so the row retires regardless of which day the server billed.
    private static func isServerApplied(
        _ row: XpLedgerEvent,
        appliedProgressionEventIds: Set<String>,
        appliedProgressionScopeKeys: Set<String>
    ) -> Bool {
        if isEventApplied(row.sourceEventId, appliedProgressionEventIds: appliedProgressionEventIds) {
            return true
        }
        if let original = row.metadata?[XpLedgerMetadataKey.originalDiscoveryEventId],
           isEventApplied(original, appliedProgressionEventIds: appliedProgressionEventIds) {
            return true
        }
        if let scopeKey = XpServerScopeKey.mirrored(for: row),
           appliedProgressionScopeKeys.contains(scopeKey) {
            return true
        }
        if let scopeKey = XpServerScopeKey.baseDiscoveryTotalOnlyScope(for: row),
           appliedProgressionScopeKeys.contains(scopeKey) {
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

    /// The event id itself, or the `srvrej_` document the server authored in its place.
    private static func isEventApplied(
        _ eventId: String,
        appliedProgressionEventIds: Set<String>
    ) -> Bool {
        guard !eventId.isEmpty else { return false }
        if appliedProgressionEventIds.contains(eventId) { return true }
        return appliedProgressionEventIds.contains(
            XpServerScopeKey.serverRejectionEventId(forClientEventId: eventId)
        )
    }
}
