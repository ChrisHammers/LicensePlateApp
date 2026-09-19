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

    // MARK: - §3.1.1 item 14 — a mirror never announces an award this device already announced
    //
    // The join is the SERVER award scope: the grant carries it as `idempotencyKey`
    // (progressionOnActivityEvent.ts:148-156) and the local row derives it
    // (`XpGainToastEligibility.mirroredServerScopeKey`). Id-independent by construction, so it holds
    // when the two sides disagree about the event id.

    /// A bonus ledger row exactly as `XpReconciliationService.appendLocalFindBonusesIfAbsent` writes
    /// it: provisional, `.provisionalDiscoveryXp`, global-scope sentinels, `itemId` = the server's
    /// scope discriminator (regionId or dayKey).
    private func bonusRow(
        id: String,
        userId: String = "u1",
        reasonCode: XpReasonCode,
        itemId: String,
        xpDelta: Int,
        sourceEventId: String = "evt-1",
        status: XpLedgerStatus = .provisional,
        createdAt: Date = .now
    ) -> XpLedgerEvent {
        XpLedgerEvent(
            id: id,
            userId: userId,
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: sourceEventId,
            sourceEventType: "region_found",
            itemId: itemId,
            grantKind: .provisionalDiscoveryXp,
            status: status,
            xpDelta: xpDelta,
            reasonCode: reasonCode,
            xpUniquenessKey: reasonCode == .lifetimeUniqueRegion
                ? XpReconciliationService.lifetimeUniqueRegionKey(userId: userId, regionId: itemId)
                : XpReconciliationService.firstFindOfDayKey(userId: userId, dayKey: itemId),
            createdAt: createdAt,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: sourceEventId]
        )
    }

    private func scopedGrant(
        grantId: String,
        amount: Int,
        reason: UserXpGrantReason,
        sourceId: String,
        idempotencyKey: String
    ) -> UserXpGrant {
        UserXpGrant(
            grantId: grantId,
            amount: amount,
            reason: reason.rawValue,
            sourceType: "activity_event",
            sourceId: sourceId,
            idempotencyKey: idempotencyKey
        )
    }

    private func sealedService(
        ledger: MockXpLedgerRepository,
        remote: MockXpGainToastRemoteReader,
        processLaunchDate: Date = Date()
    ) -> XpGainToastService {
        let service = XpGainToastService(
            xpLedger: ledger,
            remoteReader: remote,
            processLaunchDate: processLaunchDate,
            wiresLiveUpdates: false
        )
        service.configure(userId: "u1")
        service.performImmediateRefresh()
        return service
    }

    /// (1) The owner's "2 first finds of the day".
    @Test func firstFindOfDayGrantDoesNotReToastAfterTheLocalRow() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)
        #expect(service.presentation == nil)

        try? ledger.append(
            bonusRow(id: "fod-1", reasonCode: .firstFindOfDay, itemId: "2026-09-18", xpDelta: 10)
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 10)

        remote.grants = [
            scopedGrant(
                grantId: "g-fod",
                amount: 10,
                reason: .firstFindOfDay,
                sourceId: "evt-1",
                idempotencyKey: "first_find_of_day|v1|u1|2026-09-18"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.lines.first?.id == "first_of_day")
        #expect(service.presentation?.lines.first?.title == "xp.toast.group.first_of_day.single".localized(1))
        #expect(service.presentation?.totalXp == 10)
    }

    /// (2) The owner's "2 new plate bonuses".
    @Test func lifetimeUniqueRegionGrantDoesNotReToastAfterTheLocalRow() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        try? ledger.append(
            bonusRow(id: "lur-1", reasonCode: .lifetimeUniqueRegion, itemId: "TX", xpDelta: 20)
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 20)

        remote.grants = [
            scopedGrant(
                grantId: "g-lur",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "evt-1",
                idempotencyKey: "lifetime_unique_region|v1|u1|TX"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.lines.first?.id == "lifetime_unique")
        #expect(service.presentation?.lines.first?.title == "xp.toast.group.lifetime_unique.single".localized(1))
        #expect(service.presentation?.totalXp == 20)
    }

    /// (3) The late-competitive variant, and the reason this dedups on the SCOPE rather than on
    /// `sourceId|reason`: the late finder's `region_found` is never written remotely — the server
    /// authors `srvrej_<clientEventId>` (gameplayEventResolver.ts) and grants the bonuses off THAT
    /// document — so the two event ids never match while the scope still does.
    ///
    /// Deliberately the LIFETIME-UNIQUE half of that find. The first-of-day half is the known
    /// residual the owner filed as a server item: the rejection payload carries no `xpDayKey`, so the
    /// server bills that scope under the UTC day of its own resolution and the two scope strings can
    /// differ. Asserting suppression there would be a false green.
    @Test func lateCompetitiveRejectionGrantIsSuppressedDespiteTheDivergentEventId() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        try? ledger.append(
            bonusRow(
                id: "lur-late",
                reasonCode: .lifetimeUniqueRegion,
                itemId: "TX",
                xpDelta: 20,
                sourceEventId: "evt-1"
            )
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 20)

        remote.grants = [
            scopedGrant(
                grantId: "g-lur-srvrej",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "srvrej_evt-1",
                idempotencyKey: "lifetime_unique_region|v1|u1|TX"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.totalXp == 20)
    }

    /// (4) Not a blanket reason exclusion: the bonus earned on ANOTHER device of this account still
    /// announces here exactly once, because this device has no local row to have announced it.
    @Test func bonusGrantWithNoLocalRowStillToastsOnce() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        remote.grants = [
            scopedGrant(
                grantId: "g-lur-other-device",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "evt-other",
                idempotencyKey: "lifetime_unique_region|v1|u1|CA"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.lines.first?.id == "lifetime_unique")
        #expect(service.presentation?.totalXp == 20)
    }

    /// (5) The half that is easiest to forget: a bonus row written before this process launched is
    /// absorbed by the ledger baseline and never mapped, so the scope has to be registered there too
    /// or the grant doubles after every relaunch.
    @Test func baselineAbsorbedBonusRowSuppressesALaterGrant() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        try? ledger.append(
            bonusRow(
                id: "lur-old",
                reasonCode: .lifetimeUniqueRegion,
                itemId: "TX",
                xpDelta: 20,
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let service = sealedService(ledger: ledger, remote: remote)
        #expect(service.presentation == nil)

        remote.grants = [
            scopedGrant(
                grantId: "g-lur",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "evt-1",
                idempotencyKey: "lifetime_unique_region|v1|u1|TX"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// (6) ...but a VOIDED row is not an announcement. `voidLocalFindBonuses` leaves `xpDelta`
    /// positive, so the baseline's `xpDelta > 0` branch alone would register a clawed-back award and
    /// swallow the only announcement of a genuinely later grant for the same scope.
    @Test func voidedBaselineBonusRowDoesNotSuppressALaterGrant() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        try? ledger.append(
            bonusRow(
                id: "lur-voided",
                reasonCode: .lifetimeUniqueRegion,
                itemId: "TX",
                xpDelta: 20,
                status: .voided,
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let service = sealedService(ledger: ledger, remote: remote)
        #expect(service.presentation == nil)

        remote.grants = [
            scopedGrant(
                grantId: "g-lur",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "evt-1",
                idempotencyKey: "lifetime_unique_region|v1|u1|TX"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.totalXp == 20)
    }

    /// (7) The symmetric direction. Two devices, one account: the iPhone's find grants
    /// `first_find_of_day|v1|u1|D` and this device announces it from the grant; a find on THIS device
    /// later the same day mints a local row for the same scope, and the server will not pay again.
    @Test func localRowDoesNotReAnnounceAnAwardTheGrantAlreadyAnnounced() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        remote.grants = [
            scopedGrant(
                grantId: "g-fod",
                amount: 10,
                reason: .firstFindOfDay,
                sourceId: "evt-other-device",
                idempotencyKey: "first_find_of_day|v1|u1|2026-09-18"
            )
        ]
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 10)
        service.dismissManually()

        try? ledger.append(
            bonusRow(id: "fod-local", reasonCode: .firstFindOfDay, itemId: "2026-09-18", xpDelta: 10)
        )
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// (8) The same direction across the item-12 seal: history absorbed pre-seal is still proof the
    /// server has paid the scope, so a local row minted afterwards (reinstall, device transfer) must
    /// not announce XP that will never be granted again.
    @Test func grantAbsorbedPreSealSuppressesALaterLocalRow() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        remote.grants = [
            scopedGrant(
                grantId: "g-lur-history",
                amount: 20,
                reason: .lifetimeUniqueRegion,
                sourceId: "evt-history",
                idempotencyKey: "lifetime_unique_region|v1|u1|TX"
            )
        ]

        let service = sealedService(ledger: ledger, remote: remote)
        #expect(service.presentation == nil)

        try? ledger.append(
            bonusRow(id: "lur-reinstall", reasonCode: .lifetimeUniqueRegion, itemId: "TX", xpDelta: 20)
        )
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// (9) Two devices authoring the same completion event mint two `game_ended` activity events with
    /// different ids; the server dedups by SCOPE, so exactly one grant exists and its `sourceId` is
    /// the winning device's event id. On the losing device the award key never matches — only the
    /// scope does.
    @Test func completionGrantAuthoredUnderADifferentEventIdIsSuppressed() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        let sessionId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let gameInstanceId = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        try? ledger.append(
            XpLedgerEvent(
                id: "ge-local",
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: gameInstanceId,
                sourceEventId: "evt-local",
                sourceEventType: "game_ended",
                itemId: XpReasonCode.gameEnded.rawValue,
                grantKind: .tripCompletion,
                status: .provisional,
                xpDelta: 25,
                reasonCode: .gameEnded,
                xpUniquenessKey: "ge-local-key"
            )
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 25)

        remote.grants = [
            scopedGrant(
                grantId: "g-game-ended",
                amount: 25,
                reason: .gameEnded,
                sourceId: "evt-peer",
                idempotencyKey: "game_ended|v1|u1|\(gameInstanceId.uuidString)"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation?.lines.count == 1)
        #expect(service.presentation?.lines.first?.id == "game_ended")
        #expect(service.presentation?.totalXp == 25)
    }

    /// (10) The pre-existing `sourceId|reason` award key is still load-bearing: a grant whose
    /// `idempotencyKey` matches no mirrored scope (the document-id fallback) is still suppressed when
    /// the event ids agree.
    @Test func completionAwardKeyStillSuppressesAGrantWithNoMatchingScope() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        let sessionId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        try? ledger.append(
            XpLedgerEvent(
                id: "te-local",
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
                sourceEventId: "evt-trip-end",
                sourceEventType: "trip_ended",
                itemId: XpReasonCode.tripEnded.rawValue,
                grantKind: .tripCompletion,
                status: .provisional,
                xpDelta: 30,
                reasonCode: .tripEnded,
                xpUniquenessKey: "te-local-key"
            )
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 30)
        service.dismissManually()

        remote.grants = [
            scopedGrant(
                grantId: "g-trip-ended-doc-id",
                amount: 30,
                reason: .tripEnded,
                sourceId: "evt-trip-end",
                idempotencyKey: "g-trip-ended-doc-id"
            )
        ]
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }

    /// (11) The three reason-level exclusions are untouched.
    @Test func baseDiscoveryAndReturnStreakGrantsAreStillExcluded() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        remote.grants = [
            scopedGrant(
                grantId: "g-base",
                amount: 10,
                reason: .regionFoundBaseDiscovery,
                sourceId: "evt-1",
                idempotencyKey: "xp_scope|v1|u1|s1|g1|TX|base_region_discovery"
            ),
            scopedGrant(
                grantId: "g-streak",
                amount: 15,
                reason: .returnStreakDaily,
                sourceId: "2026-09-18",
                idempotencyKey: "return_streak_daily|v1|u1|2026-09-18"
            ),
        ]
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
        #expect(XpGainToastEligibility.mirroredServerScopeKey(
            for: sampleLedgerRow(reasonCode: .soloNewDiscovery)
        ) == nil)
    }

    /// (12) The mapping itself, byte-for-byte against `functions/src/progressionCore.ts:281-316`, and
    /// exhaustive: every `XpReasonCode` not listed here must map to `nil`.
    @Test func mirroredServerScopeKeyMatchesTheServerFormatForEveryMappedReason() {
        let sessionId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let gameInstanceId = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

        let expected: [XpReasonCode: String] = [
            .lifetimeUniqueRegion: "lifetime_unique_region|v1|u1|TX",
            .firstFindOfDay: "first_find_of_day|v1|u1|2026-09-18",
            .gameEnded: "game_ended|v1|u1|\(gameInstanceId.uuidString)",
            .gameFullClear: "game_full_clear|v1|u1|\(gameInstanceId.uuidString)",
            .competitiveFirstPlaceFinish: "competitive_place|1|v1|u1|\(gameInstanceId.uuidString)",
            .competitiveSecondPlace: "competitive_place|2|v1|u1|\(gameInstanceId.uuidString)",
            .competitiveThirdPlace: "competitive_place|3|v1|u1|\(gameInstanceId.uuidString)",
            .tripEnded: "trip_ended|v1|u1|\(sessionId.uuidString)",
            .tripParticipation: "trip_participation|v1|u1|\(sessionId.uuidString)",
            .tripCompetitiveFirstPlace: "trip_competitive_first|v1|u1|\(sessionId.uuidString)",
        ]

        for reason in XpReasonCode.allCases {
            let row = scopeProbeRow(reason: reason, sessionId: sessionId, gameInstanceId: gameInstanceId)
            #expect(
                XpGainToastEligibility.mirroredServerScopeKey(for: row) == expected[reason],
                "unexpected mirrored scope for \(reason.rawValue)"
            )
        }

        // A completion reason on a row that is not a completion row, or whose scoping id is the
        // global sentinel, has no server award to join against.
        let sentinelTripEnded = XpLedgerEvent(
            id: "sentinel",
            userId: "u1",
            sessionId: XpLedgerGlobalScope.sessionId,
            gameInstanceId: XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: "evt",
            sourceEventType: "trip_ended",
            itemId: XpReasonCode.tripEnded.rawValue,
            grantKind: .tripCompletion,
            status: .provisional,
            xpDelta: 30,
            reasonCode: .tripEnded,
            xpUniquenessKey: "k"
        )
        #expect(XpGainToastEligibility.mirroredServerScopeKey(for: sentinelTripEnded) == nil)

        // …and the `grantKind == .tripCompletion` guard: a completion REASON on any other kind of
        // row is not a completion award, even with a real game id.
        let wrongKindGameEnded = XpLedgerEvent(
            id: "wrong-kind",
            userId: "u1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            sourceEventId: "evt",
            sourceEventType: "game_ended",
            itemId: XpReasonCode.gameEnded.rawValue,
            grantKind: .provisionalDiscoveryXp,
            status: .final,
            xpDelta: 25,
            reasonCode: .gameEnded,
            xpUniquenessKey: "k2"
        )
        #expect(XpGainToastEligibility.mirroredServerScopeKey(for: wrongKindGameEnded) == nil)
    }

    private func scopeProbeRow(
        reason: XpReasonCode,
        sessionId: UUID,
        gameInstanceId: UUID
    ) -> XpLedgerEvent {
        let completionReasons: Set<XpReasonCode> = [
            .gameEnded, .gameFullClear,
            .competitiveFirstPlaceFinish, .competitiveSecondPlace, .competitiveThirdPlace,
            .tripEnded, .tripParticipation, .tripCompetitiveFirstPlace,
        ]
        let isCompletion = completionReasons.contains(reason)
        let itemId: String
        switch reason {
        case .firstFindOfDay: itemId = "2026-09-18"
        case .lifetimeUniqueRegion: itemId = "TX"
        default: itemId = isCompletion ? reason.rawValue : "TX"
        }
        return XpLedgerEvent(
            id: "probe-\(reason.rawValue)",
            userId: "u1",
            sessionId: isCompletion ? sessionId : XpLedgerGlobalScope.sessionId,
            gameInstanceId: isCompletion ? gameInstanceId : XpLedgerGlobalScope.gameInstanceId,
            sourceEventId: "evt-probe",
            sourceEventType: "probe",
            itemId: itemId,
            grantKind: isCompletion ? .tripCompletion : .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: reason,
            xpUniquenessKey: "probe-key-\(reason.rawValue)"
        )
    }

    /// (13) Identity-epoch replay. `configure` starts a new epoch and drops every ack set, and
    /// `establishLedgerBaseline` refuses to absorb provisional rows created in this process — so a
    /// mid-session rebind (FR-60 provision-at-consent, guest → registered link, FR-84 transfer) used
    /// to re-toast rows the user had seen seconds earlier. Row ids survive the rebind
    /// (`LocalPlayIdentityRepository.rebindLocalPlayIdentity` rewrites `userId` and
    /// `xpUniquenessKey` in place), so the process-lifetime presented set can carve them out.
    @Test func provisionalRowsPresentedBeforeAnIdentityRebindAreNotRePresented() async {
        let ledger = MockXpLedgerRepository()
        let remote = MockXpGainToastRemoteReader()
        let service = sealedService(ledger: ledger, remote: remote)

        try? ledger.append(
            bonusRow(id: "lur-inprocess", reasonCode: .lifetimeUniqueRegion, itemId: "TX", xpDelta: 20)
        )
        service.performImmediateRefresh()
        #expect(service.presentation?.totalXp == 20)
        service.dismissManually()

        // The rebind: rows keep their ids and take the new uid.
        for index in ledger.stored.indices where ledger.stored[index].userId == "u1" {
            ledger.stored[index].userId = "u2"
        }
        remote.boundUserId = "u2"
        service.configure(userId: "u2")
        service.performImmediateRefresh()

        #expect(service.presentation == nil)
    }
}
