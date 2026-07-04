//
//  DiscoveryUiProjectionBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoveryUiProjectionBuilderTests {

    @Test func foundStateStableWhileXpPending() {
        let sid = UUID()
        let gid = UUID()
        let uid = "u1"
        let discoveries = [
            GameDiscovery(
                id: "d1",
                gameInstanceId: gid,
                participantId: uid,
                targetId: "TX",
                discoveredAt: Date(timeIntervalSince1970: 100),
                inputMethod: .list
            ),
        ]
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let ledger: [XpLedgerEvent] = [
            XpLedgerEvent(
                id: "p1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "d1",
                sourceEventType: "region_found",
                itemId: "TX",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            ),
        ]
        let p = DiscoveryUiProjectionBuilder.project(
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            viewerUserId: uid,
            gameMode: .competitive,
            discoveriesForItem: discoveries,
            resolution: nil,
            ledgerEventsForItem: ledger,
            lastUpdated: Date(timeIntervalSince1970: 200)
        )
        #expect(p.viewerHasActiveDiscovery)
        #expect(p.displayState == .foundVisuallyActive)
        #expect(p.xpPhase == .provisional)
        #expect(p.xpShownDelta == 10)
    }

    @Test func transitionsToFinalWhenResolutionPresent() {
        let sid = UUID()
        let gid = UUID()
        let uid = "u1"
        let discoveries = [
            GameDiscovery(
                id: "d1",
                gameInstanceId: gid,
                participantId: uid,
                targetId: "TX",
                discoveredAt: Date(timeIntervalSince1970: 100),
                inputMethod: .list
            ),
        ]
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let ledger: [XpLedgerEvent] = [
            XpLedgerEvent(
                id: "p1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "d1",
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
                sourceEventId: "r1",
                sourceEventType: "discovery_resolution",
                itemId: "TX",
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: -6,
                reasonCode: .competitiveLateFinder,
                xpUniquenessKey: key
            ),
        ]
        let resolution = DiscoveryResolution(
            resolutionId: "r1",
            sourceEventId: "d1",
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            actorUserId: uid,
            finalOutcome: .acceptedLate,
            tripScoringOutcome: .acceptedLate,
            personalHistoryOutcome: .acceptedLate,
            finalXpAward: 4,
            xpReason: .competitiveLateFinder
        )
        let p = DiscoveryUiProjectionBuilder.project(
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            viewerUserId: uid,
            gameMode: .competitive,
            discoveriesForItem: discoveries,
            resolution: resolution,
            ledgerEventsForItem: ledger,
            lastUpdated: Date(timeIntervalSince1970: 300)
        )
        #expect(p.viewerHasActiveDiscovery)
        #expect(p.xpPhase == .final)
        #expect(p.xpShownDelta == 4)
    }

    @Test func rowPresentationKeepsPendingStatusWithoutXpAmount() {
        let row = RegionPlateRowPresentationBuilder.build(
            regionId: "TX",
            regionName: "Texas",
            projection: makeProjection(
                displayState: .foundVisuallyActive,
                xpPhase: .provisional,
                xpShownDelta: 10,
                syncState: .localOnly
            ),
            foundFallback: false
        )

        #expect(row.isVisuallyFound)
        #expect(row.showPendingBadge)
        #expect(row.detailLine == "xp.row.detail.pending_resolution".localized)
        #expect(!row.accessibilityValue.localizedCaseInsensitiveContains("xp"))
    }

    @Test func rowPresentationKeepsFairnessStatusWithoutXpAmount() {
        let row = RegionPlateRowPresentationBuilder.build(
            regionId: "TX",
            regionName: "Texas",
            projection: makeProjection(
                displayState: .foundVisuallyActive,
                xpPhase: .final,
                xpShownDelta: 4,
                syncState: .synced,
                statusBadgeText: "xp.discovery.badge.accepted_late".localized
            ),
            foundFallback: false
        )

        #expect(row.isVisuallyFound)
        #expect(!row.showPendingBadge)
        #expect(row.detailLine == "xp.discovery.badge.accepted_late".localized)
        #expect(!(row.detailLine?.localizedCaseInsensitiveContains("xp") ?? false))
        #expect(!row.accessibilityValue.localizedCaseInsensitiveContains("xp"))
    }

    @Test func rowPresentationDoesNotFallBackToFinalAwardXpText() {
        let row = RegionPlateRowPresentationBuilder.build(
            regionId: "TX",
            regionName: "Texas",
            projection: makeProjection(
                displayState: .foundVisuallyActive,
                xpPhase: .final,
                xpShownDelta: 10,
                syncState: .synced
            ),
            foundFallback: false
        )

        #expect(row.isVisuallyFound)
        #expect(row.detailLine == nil)
        #expect(!row.accessibilityValue.localizedCaseInsensitiveContains("xp"))
    }

    private func makeProjection(
        displayState: DiscoveryTileDisplayState,
        xpPhase: DiscoveryXpProjectionPhase,
        xpShownDelta: Int,
        syncState: DiscoverySyncProjectionState,
        statusBadgeText: String? = nil
    ) -> DiscoveryUiProjection {
        DiscoveryUiProjection(
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            viewerUserId: "u1",
            displayState: displayState,
            tripAttribution: ParticipantDiscoverySummary(
                firstFinderParticipantId: "u1",
                allFinderParticipantIds: ["u1"],
                summaryLabel: "Found by u1"
            ),
            viewerHasActiveDiscovery: displayState == .foundVisuallyActive,
            xpPhase: xpPhase,
            xpShownDelta: xpShownDelta,
            syncState: syncState,
            statusBadgeText: statusBadgeText,
            lastUpdated: Date(timeIntervalSince1970: 400)
        )
    }
}
