//
//  XpFeedProjectionBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpFeedProjectionBuilderTests {

    @Test func buildsPendingAndResolvedLines() {
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
                xpUniquenessKey: key,
                createdAt: Date(timeIntervalSince1970: 100)
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
                xpUniquenessKey: key,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
        ]
        let lines = XpFeedProjectionBuilder.lines(from: events) { $0 }
        #expect(lines.count == 2)
        #expect(lines[0].state == .provisional)
        #expect(lines[0].xpDisplayText.contains("10"))
        #expect(lines[1].state == .final)
        #expect(lines[1].title.contains("TX"))
    }
}
