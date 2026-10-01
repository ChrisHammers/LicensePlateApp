//
//  LedgerPendingXpTotalsSupersededFindTests.swift
//  LicensePlateAppTests
//
//  §3.1.1 item 17 — a competitive find that lost to an earlier one must not inflate the displayed
//  XP total forever.
//
//  The shape under test is what the device is actually left holding after a supersede:
//  `SyncCoordinator` deletes the local `region_found` event, `GameplayXpSyncSupport` resolves the
//  find as `.acceptedLate` (target net = base discovery XP, so nothing is voided), and three ledger
//  rows survive with `sourceEventId` = the deleted client event id — the final discovery award plus
//  the two provisional find bonuses. The server, meanwhile, never wrote that event: it authored
//  `srvrej_<clientEventId>` and granted base + `lifetime_unique_region` + `first_find_of_day` off
//  THAT document (`functions/src/gameplayEventResolver.ts`, `functions/src/progressionCore.ts`), so
//  its `appliedProgressionEvents` holds only the `srvrej_` id.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LedgerPendingXpTotalsSupersededFindTests {

    private static let userId = "u1"
    private static let regionId = "TX"
    private static let clientFindEventId = "find-late-1"
    private static let deviceDayKey = "2026-09-19"

    private static let sessionId = UUID()
    private static let gameInstanceId = UUID()

    /// The base award the device settled on after the supersede: `.acceptedLate` keeps base XP.
    private static func finalDiscoveryRow(sourceEventId: String = clientFindEventId) -> XpLedgerEvent {
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: regionId,
            xpCategory: .baseRegionDiscovery
        ).storageString
        return XpLedgerEvent(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            sourceEventId: sourceEventId,
            sourceEventType: "region_found",
            itemId: regionId,
            grantKind: .finalDiscoveryAward,
            status: .final,
            xpDelta: 10,
            reasonCode: .competitiveLateFinder,
            xpUniquenessKey: key,
            resolvedAt: Date(),
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: sourceEventId]
        )
    }

    private static func lifetimeUniqueRow(sourceEventId: String = clientFindEventId) -> XpLedgerEvent {
        XpLedgerEvent(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: sourceEventId,
            sourceEventType: "region_found",
            itemId: regionId,
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 20,
            reasonCode: .lifetimeUniqueRegion,
            xpUniquenessKey: XpLedgerKeyBuilder.uniquenessKey(
                userId: userId,
                sessionId: XpLedgerGlobalScope.sessionId,
                gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
                itemId: regionId,
                xpCategory: .lifetimeUniqueRegion
            ).storageString,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: sourceEventId]
        )
    }

    private static func firstFindOfDayRow(
        sourceEventId: String = clientFindEventId,
        dayKey: String = deviceDayKey
    ) -> XpLedgerEvent {
        XpLedgerEvent(
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: sourceEventId,
            sourceEventType: "region_found",
            itemId: dayKey,
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .firstFindOfDay,
            xpUniquenessKey: XpLedgerKeyBuilder.uniquenessKey(
                userId: userId,
                sessionId: XpLedgerGlobalScope.sessionId,
                gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
                itemId: dayKey,
                xpCategory: .firstFindOfDay
            ).storageString,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: sourceEventId]
        )
    }

    private static func snapshot(
        totalXp: Int,
        appliedEventIds: Set<String>,
        appliedScopeKeys: Set<String>
    ) -> UserProgressionSnapshot {
        UserProgressionSnapshot(
            totalXp: totalXp,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: appliedEventIds,
            appliedProgressionScopeKeys: appliedScopeKeys
        )
    }

    // MARK: - The defect

    /// The orphan: the server paid all three awards off `srvrej_<clientEventId>`, so the displayed
    /// total must equal the server total. Before item 17 this read `serverXp + 40`, forever.
    @Test func supersededCompetitiveFindDoesNotInflateTheDisplayedTotal() {
        let rows = [Self.finalDiscoveryRow(), Self.lifetimeUniqueRow(), Self.firstFindOfDayRow()]
        let server = Self.snapshot(
            totalXp: 140,
            appliedEventIds: ["srvrej_\(Self.clientFindEventId)"],
            appliedScopeKeys: [
                "lifetime_unique_region|v1|\(Self.userId)|\(Self.regionId)",
                "first_find_of_day|v1|\(Self.userId)|\(Self.deviceDayKey)",
            ]
        )

        let totals = ProgressionDisplayTotalsResolver.resolve(
            userId: Self.userId,
            ledgerEvents: rows,
            serverSnapshot: server,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        )

        #expect(totals.openProvisionalXp == 0)
        #expect(totals.displayedTotalXp == 140)
    }

    /// §3.1.1 item 18 robustness: the server-authored rejection payload carries no `xpDayKey`, so
    /// the server can bill `first_find_of_day` under the UTC day of the REJECTION while the device's
    /// row carries the device's day. The scope strings then disagree — and the row must still retire,
    /// because the `srvrej_` event id carries no day at all.
    @Test func supersededFindRetiresEvenWhenTheServerBilledADifferentDay() {
        let rows = [Self.finalDiscoveryRow(), Self.lifetimeUniqueRow(), Self.firstFindOfDayRow()]
        let server = Self.snapshot(
            totalXp: 140,
            appliedEventIds: ["srvrej_\(Self.clientFindEventId)"],
            appliedScopeKeys: [
                "lifetime_unique_region|v1|\(Self.userId)|\(Self.regionId)",
                // The server's UTC day, one ahead of the device's local day.
                "first_find_of_day|v1|\(Self.userId)|2026-09-20",
            ]
        )

        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: rows,
            appliedProgressionEventIds: server.appliedProgressionEventIds,
            appliedProgressionScopeKeys: server.appliedProgressionScopeKeys
        )
        #expect(open == 0)
    }

    /// The id-independent half of the join, on its own: this account already took the
    /// once-per-lifetime bonus for the plate (on another device, under another event), so the server
    /// will never grant it again and the local row must not keep adding to the total.
    @Test func bonusRowRetiresOnAnAppliedScopeEvenWhenNoEventIdMatches() {
        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: [Self.lifetimeUniqueRow()],
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: [
                "lifetime_unique_region|v1|\(Self.userId)|\(Self.regionId)"
            ]
        )
        #expect(open == 0)
    }

    // MARK: - Regression guards

    /// The normal accepted find still retires by its own event id, with no scopes involved.
    @Test func acceptedFindStillRetiresByItsOwnEventId() {
        let rows = [
            Self.finalDiscoveryRow(sourceEventId: "find-ok-1"),
            Self.lifetimeUniqueRow(sourceEventId: "find-ok-1"),
            Self.firstFindOfDayRow(sourceEventId: "find-ok-1"),
        ]
        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: rows,
            appliedProgressionEventIds: ["find-ok-1"],
            appliedProgressionScopeKeys: []
        )
        #expect(open == 0)
    }

    /// Offline, or simply not yet reconciled: nothing on the server mentions this find, so all three
    /// rows keep counting. OD-16 — the device's own decision is what the player sees.
    @Test func offlineFindWithNoServerStateStillCounts() {
        let rows = [Self.finalDiscoveryRow(), Self.lifetimeUniqueRow(), Self.firstFindOfDayRow()]
        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: rows,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        #expect(open == 40)
    }

    /// A DIFFERENT find's rejection must not retire this find's rows: the `srvrej_` join is built on
    /// the row's own event id, not on the presence of any rejection.
    @Test func anotherFindsRejectionDoesNotRetireThisFind() {
        let rows = [Self.finalDiscoveryRow(), Self.lifetimeUniqueRow(), Self.firstFindOfDayRow()]
        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: rows,
            appliedProgressionEventIds: ["srvrej_some-other-find"],
            appliedProgressionScopeKeys: []
        )
        #expect(open == 40)
    }

    /// The return-streak branch is untouched: it retires on its own daily scope and on nothing else.
    @Test func returnStreakRetirementIsUnchanged() {
        let dayKey = "2026-09-19"
        let row = XpLedgerEvent(
            userId: Self.userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: "return_streak|\(dayKey)",
            sourceEventType: "return_streak",
            itemId: dayKey,
            grantKind: .milestoneUnlock,
            status: .final,
            xpDelta: 5,
            reasonCode: .returnStreakDaily,
            xpUniquenessKey: "uk-\(dayKey)"
        )

        let unrelated = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: ["srvrej_some-other-find", "some-other-event"],
            appliedProgressionScopeKeys: ["first_find_of_day|v1|\(Self.userId)|\(dayKey)"]
        )
        #expect(unrelated == 5)

        let settled = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: [
                ReturnStreakXpScopeKey.daily(userId: Self.userId, dayKey: dayKey)
            ]
        )
        #expect(settled == 0)
    }

    /// Join 3 is not limited to the two find bonuses: `XpServerScopeKey.mirrored(for:)` also maps the
    /// completion awards, and those rows are written `.provisional`, so they feed the open sum. A
    /// completion row retires when the server has applied that award's scope, whichever event paid
    /// it — two authors of the same completion, or the same account ending the trip on another
    /// device (§3.1.1 item 19's world).
    @Test func completionRowRetiresOnAnAppliedScopeEvenWhenNoEventIdMatches() {
        let sessionId = UUID()
        let row = XpLedgerEvent(
            userId: Self.userId,
            sessionId: sessionId,
            gameInstanceId: UUID(),
            sourceEventId: "evt-local-trip-ended",
            sourceEventType: "trip_ended",
            itemId: XpReasonCode.tripEnded.rawValue,
            grantKind: .tripCompletion,
            status: .provisional,
            xpDelta: 30,
            reasonCode: .tripEnded,
            xpUniquenessKey: "uk-trip-ended"
        )

        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: ["evt-peer-trip-ended"],
            appliedProgressionScopeKeys: []
        )
        #expect(open == 30)

        let settled = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: ["evt-peer-trip-ended"],
            appliedProgressionScopeKeys: ["trip_ended|v1|\(Self.userId)|\(sessionId.uuidString)"]
        )
        #expect(settled == 0)
    }

    /// The exact server strings this retirement joins on, pinned so a rename on either side breaks
    /// here rather than silently un-retiring rows.
    @Test func serverIdentityStringsMatchTheFunctionsSource() {
        #expect(
            XpServerScopeKey.serverRejectionEventId(forClientEventId: "abc") == "srvrej_abc"
        )
        #expect(
            XpServerScopeKey.mirrored(for: Self.lifetimeUniqueRow())
                == "lifetime_unique_region|v1|\(Self.userId)|\(Self.regionId)"
        )
        #expect(
            XpServerScopeKey.mirrored(for: Self.firstFindOfDayRow())
                == "first_find_of_day|v1|\(Self.userId)|\(Self.deviceDayKey)"
        )
        // The base discovery award has no mirrored scope here: it retires by event id (or its
        // `srvrej_` form), and its server mirror is excluded from toasting by reason.
        #expect(XpServerScopeKey.mirrored(for: Self.finalDiscoveryRow()) == nil)
    }
}
