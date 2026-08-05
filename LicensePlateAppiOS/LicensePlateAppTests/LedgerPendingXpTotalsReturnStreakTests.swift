//
//  LedgerPendingXpTotalsReturnStreakTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LedgerPendingXpTotalsReturnStreakTests {

    @Test func returnStreakFinalInflatesUntilScopeApplied() {
        let dayKey = "2026-07-11"
        let userId = "u1"
        let row = XpLedgerEvent(
            userId: userId,
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

        let open = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        #expect(open == 5)

        let scopeKey = ReturnStreakXpScopeKey.daily(userId: userId, dayKey: dayKey)
        let settled = LedgerPendingXpTotals.openProvisionalSum(
            from: [row],
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: [scopeKey]
        )
        #expect(settled == 0)
    }
}
