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
        reasonCode: XpReasonCode = .soloNewDiscovery,
        itemId: String = "TX",
        status: XpLedgerStatus = .final,
        metadata: [String: String]? = nil
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
            status: status,
            xpDelta: xpDelta,
            reasonCode: reasonCode,
            xpUniquenessKey: key,
            metadata: metadata
        )
    }

    private func sampleGrant(
        grantId: String = "grant-1",
        amount: Int = 15,
        reason: String = UserXpGrantReason.competitiveFirstPlaceFinish.rawValue,
        achievementId: String? = nil
    ) -> UserXpGrant {
        UserXpGrant(
            grantId: grantId,
            amount: amount,
            reason: reason,
            sourceType: "activity_event",
            sourceId: "game-ended-1",
            idempotencyKey: grantId,
            achievementId: achievementId
        )
    }

    @Test func eligibilityRejectsNonPositiveLedgerAndDuplicateDiscoveryRemote() {
        let negative = sampleLedgerRow(xpDelta: -6, grantKind: .reconciliationAdjustment)
        #expect(!XpGainToastEligibility.shouldToastLedgerRow(negative))

        let zero = sampleLedgerRow(xpDelta: 0)
        #expect(!XpGainToastEligibility.shouldToastLedgerRow(zero))

        let milestone = sampleLedgerRow(
            grantKind: .milestoneUnlock,
            reasonCode: .milestoneUnlock,
            itemId: "ach-1"
        )
        #expect(XpGainToastEligibility.shouldToastLedgerRow(milestone))

        let discoveryRemote = sampleGrant(
            grantId: "remote-discovery",
            amount: 10,
            reason: UserXpGrantReason.regionFoundBaseDiscovery.rawValue
        )
        #expect(!XpGainToastEligibility.shouldToastRemoteGrant(discoveryRemote))

        let achievementGrant = sampleGrant(
            grantId: "ach-grant",
            amount: 20,
            reason: UserXpGrantReason.achievementUnlock.rawValue,
            achievementId: "ach-1"
        )
        #expect(XpGainToastEligibility.shouldToastRemoteGrant(achievementGrant))
    }

    @Test func mapperSkipsDuplicateDiscoveryRemoteGrant() {
        let catalog = ProgressionCatalog.bundledDefault
        let discoveryRemote = sampleGrant(
            grantId: "remote-discovery",
            amount: 10,
            reason: UserXpGrantReason.regionFoundBaseDiscovery.rawValue
        )
        #expect(XpGainToastSourceMapper.ingestEvent(from: discoveryRemote, catalog: catalog) == nil)
    }

    @Test func mapperIncludesAchievementRemoteGrant() {
        let catalog = ProgressionCatalog.bundledDefault
        let grant = sampleGrant(
            grantId: "ach-grant",
            amount: 25,
            reason: UserXpGrantReason.achievementUnlock.rawValue,
            achievementId: "first_win"
        )
        let event = XpGainToastSourceMapper.ingestEvent(from: grant, catalog: catalog)
        #expect(event?.groupId == "achievement")
        #expect(event?.xpAmount == 25)
    }

    @Test func aggregatorCollapsesThreeDiscoveriesIntoOneLine() {
        let catalog = ProgressionCatalog.bundledDefault
        let events = [
            XpGainToastIngestEvent(
                sourceId: "ledger|1",
                groupId: "discovery",
                xpAmount: 10,
                displayToken: "Texas",
                createdAt: Date(timeIntervalSince1970: 1),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "ledger|2",
                groupId: "discovery",
                xpAmount: 10,
                displayToken: "California",
                createdAt: Date(timeIntervalSince1970: 2),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "ledger|3",
                groupId: "discovery",
                xpAmount: 10,
                displayToken: "Florida",
                createdAt: Date(timeIntervalSince1970: 3),
                isProvisionalDiscovery: false
            ),
        ]
        let presentation = XpGainToastAggregator.aggregate(
            events: events,
            catalog: catalog,
            dismissDuration: 4
        )
        #expect(presentation.totalXp == 30)
        #expect(presentation.lines.count == 1)
        #expect(presentation.lines.first?.id == "discovery")
        #expect(presentation.lines.first?.xpAmount == 30)
        #expect(presentation.lines.first?.title == "xp.toast.group.discovery.multi".localized("Texas", 2))
    }

    @Test func aggregatorSummarizesAchievementsStreakAndDiscovery() {
        let catalog = ProgressionCatalog.bundledDefault
        let events = [
            XpGainToastIngestEvent(
                sourceId: "ledger|1",
                groupId: "discovery",
                xpAmount: 10,
                displayToken: "Texas",
                createdAt: Date(timeIntervalSince1970: 1),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "ledger|2",
                groupId: "return_streak",
                xpAmount: 5,
                displayToken: "2",
                createdAt: Date(timeIntervalSince1970: 2),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "grant|1",
                groupId: "achievement",
                xpAmount: 20,
                displayToken: "ach-1",
                createdAt: Date(timeIntervalSince1970: 3),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "grant|2",
                groupId: "achievement",
                xpAmount: 20,
                displayToken: "ach-2",
                createdAt: Date(timeIntervalSince1970: 4),
                isProvisionalDiscovery: false
            ),
            XpGainToastIngestEvent(
                sourceId: "grant|3",
                groupId: "achievement",
                xpAmount: 20,
                displayToken: "ach-3",
                createdAt: Date(timeIntervalSince1970: 5),
                isProvisionalDiscovery: false
            ),
        ]
        let presentation = XpGainToastAggregator.aggregate(
            events: events,
            catalog: catalog,
            dismissDuration: 4
        )
        #expect(presentation.totalXp == 75)
        #expect(presentation.lines.count == 3)
        #expect(presentation.lines.map(\.id) == ["discovery", "achievement", "return_streak"])
        #expect(presentation.lines[1].title == "xp.toast.group.achievement.multi".localized(3))
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
        #expect(service.presentation?.lines.first?.id == "discovery")
        #expect(service.presentation?.totalXp == 10)
    }

    @Test func offlineProvisionalToastsWithoutRemoteSnapshot() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        try? ledger.append(
            sampleLedgerRow(
                id: "prov-1",
                grantKind: .provisionalDiscoveryXp,
                reasonCode: .discoveryClaimPendingResolution,
                status: .provisional
            )
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 10)
        #expect(service.presentation?.lines.first?.id == "discovery")
    }

    @Test func settledFinalDoesNotRetoastSameScope() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()

        let provisional = sampleLedgerRow(
            id: "prov-1",
            grantKind: .provisionalDiscoveryXp,
            reasonCode: .discoveryClaimPendingResolution,
            status: .provisional
        )
        try? ledger.append(provisional)
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 10)
        service.dismissManually()

        var final = provisional
        final = XpLedgerEvent(
            id: "final-1",
            userId: provisional.userId,
            sessionId: provisional.sessionId,
            gameInstanceId: provisional.gameInstanceId,
            sourceEventId: provisional.sourceEventId,
            sourceEventType: provisional.sourceEventType,
            itemId: provisional.itemId,
            grantKind: .finalDiscoveryAward,
            status: .final,
            xpDelta: 10,
            reasonCode: .soloNewDiscovery,
            xpUniquenessKey: provisional.xpUniquenessKey
        )
        try? ledger.append(final)
        service.performImmediateRefresh()
        #expect(service.presentation == nil)
    }

    @Test func coalescesMultipleDiscoveriesIntoOneGroupedLine() async {
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
        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.totalXp == 20)
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
        #expect(service.presentation?.lines.contains(where: { $0.id == "discovery" }) == true)
        #expect(service.presentation?.lines.contains(where: { $0.id == "competitive_place" }) == true)
        #expect(service.presentation?.totalXp == 25)
    }

    @Test func rankBandBuilderComputesProgressSegments() {
        let catalog = ProgressionCatalog.bundledDefault
        let band = XpGainToastRankBandBuilder.build(
            totalXpBeforeBurst: 900,
            burstXpGained: 150,
            catalog: catalog
        )
        #expect(band != nil)
        #expect(band?.burstXpGained == 150)
        #expect(band?.progressAfterBurst ?? 0 > band?.progressBeforeBurst ?? 1)
        #expect(band?.isMaxRank == false)
        #expect(band?.xpToNextRank ?? -1 >= 0)
    }

    @Test func rankBandBuilderReturnsNilWhenRankProgressionDisabled() {
        var catalog = ProgressionCatalog.bundledDefault
        catalog.presentation.rankProgressionEnabled = false
        #expect(
            XpGainToastRankBandBuilder.build(
                totalXpBeforeBurst: 500,
                burstXpGained: 10,
                catalog: catalog
            ) == nil
        )
    }
}
