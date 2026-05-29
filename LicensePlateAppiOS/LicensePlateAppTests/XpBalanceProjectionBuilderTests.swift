//
//  XpBalanceProjectionBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpBalanceProjectionBuilderTests {

    @Test func separatesFinalAndProvisional() {
        let sid = UUID()
        let gid = UUID()
        let uid = "u1"
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let events: [XpLedgerEvent] = [
            XpLedgerEvent(
                id: "p1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "src1",
                sourceEventType: "region_found",
                itemId: "TX",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            ),
            XpLedgerEvent(
                id: "a1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "res1",
                sourceEventType: "discovery_resolution",
                itemId: "TX",
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: -6,
                reasonCode: .competitiveLateFinder,
                xpUniquenessKey: key
            ),
        ]
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let b = XpBalanceProjectionBuilder.build(
            userId: uid,
            sessionId: sid,
            gameInstanceId: gid,
            ledgerEvents: events,
            now: now
        )
        #expect(b.totalXpFinal == 4)
        #expect(b.totalXpProvisional == 10)
        #expect(b.displayXp == 4)
        #expect(b.pendingAdjustmentCount == 1)
        #expect(b.lastRecomputedAt == now)
    }
}
