//
//  XpProgressViewModelTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct XpProgressViewModelTests {

    @Test func refreshUsesSnapshotProviderAndLedgerProvisional() throws {
        let ledger = MockXpLedgerRepository()
        let sid = UUID()
        let gid = UUID()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "p1",
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "us-ca",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try ledger.append(
            XpLedgerEvent(
                userId: "p1",
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "e1",
                sourceEventType: "region_found",
                itemId: "us-ca",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            )
        )

        let vm = XpProgressViewModel(
            userId: "p1",
            xpLedger: ledger,
            snapshotProvider: { 200 }
        )
        #expect(vm.serverFinalXp == 200)
        #expect(vm.ledgerProvisionalPending == 10)
    }

    @Test func refreshClearsProvisionalWhenNoRows() throws {
        let ledger = MockXpLedgerRepository()
        let vm = XpProgressViewModel(
            userId: "p2",
            xpLedger: ledger,
            snapshotProvider: { 0 }
        )
        #expect(vm.ledgerProvisionalPending == 0)
    }
}
