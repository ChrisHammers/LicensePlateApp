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
    // §3.1.1 item 12: sealed and bound to "u1" by default, because every test below configures the
    // service for "u1". Tests that want the unsealed / rebinding / other-uid cases say so explicitly.
    var hasReceivedServerSnapshot = true
    var bindingGeneration = 0
    var boundUserId: String? = "u1"
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

    // MARK: - §3.1.1 item 12 — the remote history line is the first SERVER-CONFIRMED snapshot

    private func lifetimeHistory() -> [UserXpGrant] {
        [
            sampleGrant(
                grantId: "g-ach-1",
                amount: 20,
                reason: UserXpGrantReason.achievementUnlock.rawValue,
                achievementId: "ach-1"
            ),
            sampleGrant(grantId: "g-place-1", amount: 15),
            sampleGrant(
                grantId: "g-legacy",
                amount: 4_785,
                reason: UserXpGrantReason.legacyUnledgeredBalance.rawValue
            ),
        ]
    }

    /// THE item-12 regression: delete + reinstall, sign-in, FR-84 transfer. The 80 ms baseline runs
    /// before the listener's first (server) snapshot, and on today's code the whole lifetime bursts.
    @Test func remoteHistoryArrivingAfterTheFirstRefreshIsAbsorbedNotToasted() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false
        remote.hasReceivedServerSnapshot = false

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        // One round trip later the server's first snapshot lands, carrying every grant ever written.
        remote.grants = lifetimeHistory()
        remote.hasReceivedInitialSnapshot = true
        remote.hasReceivedServerSnapshot = true
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// The invariant a blanket "never toast remote at launch" fix would break.
    @Test func grantsArrivingAfterTheServerSealStillToast() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.grants = [sampleGrant(grantId: "g1", amount: 15)]

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants.append(
            sampleGrant(
                grantId: "g2",
                amount: 40,
                reason: UserXpGrantReason.achievementUnlock.rawValue,
                achievementId: "ach-2"
            )
        )
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.totalXp == 40)
    }

    /// The case a literal "the first snapshot is the watermark" gets wrong: the cache held a subset,
    /// and the server snapshot adds OLDER documents the cache never had.
    @Test func cachedThenServerSnapshotAddingOlderGrantsToastsNothing() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedServerSnapshot = false
        remote.grants = [
            sampleGrant(grantId: "g1", amount: 15),
            sampleGrant(grantId: "g2", amount: 15),
        ]

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants = [
            sampleGrant(grantId: "g0", amount: 15),
            sampleGrant(grantId: "g1", amount: 15),
            sampleGrant(grantId: "g2", amount: 15),
            sampleGrant(grantId: "g3", amount: 15),
        ]
        remote.hasReceivedServerSnapshot = true
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// A denied or failed listen sets `hasReceivedInitialSnapshot` and leaves the seal closed
    /// (XpGrantRemoteRepository's error branch). It is not evidence about the server's grant set.
    @Test func listenerErrorDoesNotSettleGrantBaseline() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = true
        remote.hasReceivedServerSnapshot = false
        remote.grants = lifetimeHistory()

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants.append(sampleGrant(grantId: "g-late", amount: 15))
        remote.hasReceivedServerSnapshot = true
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// Firestore raises an EMPTY from-cache snapshot as soon as it goes offline, so
    /// `hasReceivedInitialSnapshot` can be true with `grants == []` and nothing server-confirmed.
    @Test func offlineLaunchWithEmptyCacheAbsorbsHistoryWhenNetworkReturns() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = true
        remote.hasReceivedServerSnapshot = false
        remote.grants = []

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants = lifetimeHistory()
        remote.hasReceivedServerSnapshot = true
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// A stop/start re-arms the seal by construction — no `configure` needed, so the fix does not
    /// depend on RootView's call ordering.
    @Test func rebindingTheGrantsListenerReSealsAndAbsorbsTheNewBindingsHistory() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.grants = [sampleGrant(grantId: "g1", amount: 15)]

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        // The listener is torn down and rebound: a new binding generation, nothing server-confirmed.
        remote.bindingGeneration = 2
        remote.hasReceivedServerSnapshot = false
        remote.grants = []
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants = [
            sampleGrant(grantId: "gA", amount: 15),
            sampleGrant(
                grantId: "gB",
                amount: 20,
                reason: UserXpGrantReason.achievementUnlock.rawValue,
                achievementId: "ach-3"
            ),
        ]
        remote.hasReceivedServerSnapshot = true
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// Fail closed: while the repository is bound to a different identity its grants are neither
    /// presented nor absorbed into this identity's acknowledged set.
    @Test func remoteGrantsAreIgnoredWhileTheListenerIsBoundToAnotherUid() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.boundUserId = "u2"
        remote.grants = [sampleGrant(grantId: "g-u2", amount: 30)]

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        // The binding catches up to this identity in the same step a fresh grant lands: everything in
        // that first sealing view is history, not a gain. Pre-item-12 this toasted 12 XP — the first
        // refresh had absorbed the mismatched binding's grant, leaving g-live the only unseen id —
        // so this step is what pins the fail-closed guard against the old code.
        remote.boundUserId = "u1"
        remote.grants.append(sampleGrant(grantId: "g-live", amount: 12))
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        // ...and the guard is not a permanent mute.
        remote.grants.append(sampleGrant(grantId: "g-later", amount: 7))
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 7)
    }

    /// The offline invariant in its strongest form: nothing remote has been seen at all.
    @Test func offlineProvisionalToastsBeforeTheServerSnapshotSeal() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false
        remote.hasReceivedServerSnapshot = false

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

    /// The ledger half of the baseline is never gated on anything remote.
    @Test func ledgerBaselineIsEstablishedEvenWhenTheSealNeverArrives() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.hasReceivedInitialSnapshot = false
        remote.hasReceivedServerSnapshot = false
        try? ledger.append(sampleLedgerRow())

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

    /// A migration seal is bookkeeping, not a gain — even squarely post-seal.
    @Test func legacyUnledgeredBalanceGrantNeverToasts() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()

        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        #expect(service.presentation == nil)

        remote.grants = [
            sampleGrant(
                grantId: "g-legacy",
                amount: 4_785,
                reason: UserXpGrantReason.legacyUnledgeredBalance.rawValue
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    @Test func eligibilityRejectsTheLegacyUnledgeredBalanceGrant() {
        let legacy = sampleGrant(
            grantId: "g-legacy",
            amount: 4_785,
            reason: UserXpGrantReason.legacyUnledgeredBalance.rawValue
        )
        #expect(!XpGainToastEligibility.shouldToastRemoteGrant(legacy))
        #expect(XpGainToastSourceMapper.ingestEvent(
            from: legacy,
            catalog: ProgressionCatalog.bundledDefault
        ) == nil)
    }

    /// The per-award dedup still holds in the post-seal world, rather than being masked by absorption.
    @Test func mirroredServerGrantForALocallyToastedAwardStillDoesNotToastAfterTheSeal() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()

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
                id: "trip-1",
                xpDelta: 30,
                grantKind: .tripCompletion,
                reasonCode: .tripEnded
            )
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 30)
        service.dismissManually()

        // The server grant mirroring the same award: same `sourceId|reason` as the local row.
        remote.grants = [
            UserXpGrant(
                grantId: "g-trip-ended",
                amount: 30,
                reason: UserXpGrantReason.tripEnded.rawValue,
                sourceType: "activity_event",
                sourceId: "src-trip-1",
                idempotencyKey: "g-trip-ended"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }
}
