//
//  XpGainToastServiceTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
private final class MockXpGainToastRemoteReader: XpGainToastRemoteReading {
    var grants: [UserXpGrant] = []
    var hasReceivedInitialSnapshot = true
}

@MainActor
struct XpGainToastServiceTests {

    private func sampleLedgerRow(
        id: String = "row-1",
        userId: String = "u1",
        xpDelta: Int = 10,
        grantKind: XpGrantKind = .finalDiscoveryAward,
        itemId: String = "TX"
    ) -> XpLedgerEvent {
        let sid = UUID()
        let gid = UUID()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: userId,
            sessionId: sid,
            gameInstanceId: gid,
            itemId: itemId,
            xpCategory: .baseRegionDiscovery
        ).storageString
        return XpLedgerEvent(
            id: id,
            userId: userId,
            sessionId: sid,
            gameInstanceId: gid,
            sourceEventId: "src-\(id)",
            sourceEventType: "region_found",
            itemId: itemId,
            grantKind: grantKind,
            status: .final,
            xpDelta: xpDelta,
            reasonCode: .soloNewDiscovery,
            xpUniquenessKey: key
        )
    }

    private func sampleGrant(
        grantId: String = "grant-1",
        amount: Int = 15,
        reason: String = UserXpGrantReason.competitiveFirstPlaceFinish.rawValue
    ) -> UserXpGrant {
        UserXpGrant(
            grantId: grantId,
            amount: amount,
            reason: reason,
            sourceType: "activity_event",
            sourceId: "game-ended-1",
            idempotencyKey: grantId
        )
    }

    @Test func eligibilityRejectsNegativeLedgerAndAchievementRemote() {
        let negative = sampleLedgerRow(xpDelta: -6, grantKind: .reconciliationAdjustment)
        #expect(!XpGainToastEligibility.shouldToastLedgerRow(negative))

        let milestone = sampleLedgerRow(grantKind: .milestoneUnlock)
        #expect(!XpGainToastEligibility.shouldToastLedgerRow(milestone))

        var achievementGrant = sampleGrant(reason: UserXpGrantReason.achievementUnlock.rawValue)
        achievementGrant.achievementId = "ach-1"
        #expect(!XpGainToastEligibility.shouldToastRemoteGrant(achievementGrant))

        let discoveryRemote = sampleGrant(
            grantId: "remote-discovery",
            amount: 10,
            reason: UserXpGrantReason.regionFoundBaseDiscovery.rawValue
        )
        #expect(!XpGainToastEligibility.shouldToastRemoteGrant(discoveryRemote))
    }

    @Test func lineBuilderMapsCompetitiveWinGrant() {
        let grant = sampleGrant()
        let line = XpGainToastLineBuilder.line(from: grant)
        #expect(line != nil)
        #expect(line?.id == "grant|\(grant.grantId)")
        #expect(line?.title == "xp.toast.grant.competitive_win.title".localized)
    }

    @Test func baselineSkipsHistoricalRows() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        try? ledger.append(sampleLedgerRow())
        remote.grants = [sampleGrant()]

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()

        #expect(service.presentation == nil)

        try? ledger.append(sampleLedgerRow(id: "row-2", itemId: "CA"))
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.lines.first?.id == "ledger|row-2")
    }

    @Test func coalescesMultipleLedgerGainsIntoOneToast() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()

        try? ledger.append(sampleLedgerRow(id: "row-1", itemId: "TX"))
        service.performImmediateRefresh()
        #expect(service.presentation?.lines.count == 1)

        try? ledger.append(sampleLedgerRow(id: "row-2", itemId: "CA"))
        service.performImmediateRefresh()
        #expect(service.presentation?.lines.count == 2)
    }

    @Test func remoteCompetitiveWinPresentsWithoutDuplicateDiscoveryGrant() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()

        try? ledger.append(sampleLedgerRow(id: "row-1"))
        remote.grants = [
            sampleGrant(
                grantId: "remote-discovery",
                amount: 10,
                reason: UserXpGrantReason.regionFoundBaseDiscovery.rawValue
            ),
            sampleGrant(grantId: "remote-win", amount: 15)
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 2)
        #expect(service.presentation?.lines.contains(where: { $0.id == "ledger|row-1" }) == true)
        #expect(service.presentation?.lines.contains(where: { $0.id == "grant|remote-win" }) == true)
        #expect(service.presentation?.lines.contains(where: { $0.id == "grant|remote-discovery" }) == false)
    }
}
