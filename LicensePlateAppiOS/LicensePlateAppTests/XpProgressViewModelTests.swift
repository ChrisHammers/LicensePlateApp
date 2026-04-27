//
//  XpProgressViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 17.1 — XP display fallback when server progression snapshot is absent.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct XpProgressViewModelTests {

    @Test func missingServerSnapshotUsesLocalPendingXpFallback() async throws {
        let ledger = MockXpLedgerRepository()
        try ledger.append(Self.event(userId: "user", xpDelta: 10))

        let viewModel = XpProgressViewModel(
            userId: "user",
            xpLedger: ledger,
            snapshotProvider: { nil }
        )

        #expect(viewModel.serverFinalXp == nil)
        #expect(viewModel.ledgerProvisionalPending == 10)
        #expect(viewModel.displayedTotalXp == 10)
        #expect(viewModel.isUsingLocalFallback == true)
    }

    @Test func serverSnapshotStillCombinesWithLocalPendingXp() async throws {
        let ledger = MockXpLedgerRepository()
        try ledger.append(Self.event(userId: "user", xpDelta: 15))

        let viewModel = XpProgressViewModel(
            userId: "user",
            xpLedger: ledger,
            snapshotProvider: { 100 }
        )

        #expect(viewModel.serverFinalXp == 100)
        #expect(viewModel.ledgerProvisionalPending == 15)
        #expect(viewModel.displayedTotalXp == 115)
        #expect(viewModel.isUsingLocalFallback == false)
    }

    private static func event(userId: String, xpDelta: Int) -> XpLedgerEvent {
        XpLedgerEvent(
            userId: userId,
            sessionId: UUID(),
            gameInstanceId: UUID(),
            sourceEventId: UUID().uuidString,
            sourceEventType: "region_found",
            itemId: "us-ca",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: xpDelta,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: UUID().uuidString
        )
    }
}
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
