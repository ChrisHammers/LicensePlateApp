//
//  ProgressionDisplayTotalsTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionDisplayTotalsTests {

    @Test func displayedTotalIsServerPlusOpenProvisional() {
        let sessionId = UUID()
        let gameId = UUID()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let provisional = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "find-1",
            sourceEventType: "region_found",
            itemId: "TX",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 15,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: key
        )
        let server = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        let totals = ProgressionDisplayTotalsResolver.resolve(
            userId: "u1",
            ledgerEvents: [provisional],
            serverSnapshot: server,
            verifiedGrantSum: 999,
            hasReceivedGrantSnapshot: true
        )
        #expect(totals.serverXp == 100)
        #expect(totals.openProvisionalXp == 15)
        #expect(totals.displayedTotalXp == 115)
        #expect(totals.isXpGrantLedgerVerified == false)
        #expect(totals.verifiedGrantSum == nil)
    }

    @Test func appliedEventExcludesProvisionalFromDisplay() {
        let sessionId = UUID()
        let gameId = UUID()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let provisional = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "find-1",
            sourceEventType: "region_found",
            itemId: "TX",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 15,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: key
        )
        let server = UserProgressionSnapshot(
            totalXp: 115,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: ["find-1"],
            appliedProgressionScopeKeys: []
        )
        let totals = ProgressionDisplayTotalsResolver.resolve(
            userId: "u1",
            ledgerEvents: [provisional],
            serverSnapshot: server,
            verifiedGrantSum: 115,
            hasReceivedGrantSnapshot: true
        )
        #expect(totals.openProvisionalXp == 0)
        #expect(totals.displayedTotalXp == 115)
        #expect(totals.isXpGrantLedgerVerified == true)
    }

    @Test func unsettledFinalMirrorCountsUntilServerApplies() {
        let sessionId = UUID()
        let gameId = UUID()
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let finalMirror = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "find-1",
            sourceEventType: "region_found",
            itemId: "TX",
            grantKind: .finalDiscoveryAward,
            status: .final,
            xpDelta: 15,
            reasonCode: .competitiveFirstFinder,
            xpUniquenessKey: key,
            metadata: [XpLedgerMetadataKey.originalDiscoveryEventId: "find-1"]
        )
        let server = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        let before = ProgressionDisplayTotalsResolver.resolve(
            userId: "u1",
            ledgerEvents: [finalMirror],
            serverSnapshot: server,
            verifiedGrantSum: nil,
            hasReceivedGrantSnapshot: false
        )
        #expect(before.displayedTotalXp == 115)

        let afterServer = UserProgressionSnapshot(
            totalXp: 115,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: ["find-1"],
            appliedProgressionScopeKeys: []
        )
        let after = ProgressionDisplayTotalsResolver.resolve(
            userId: "u1",
            ledgerEvents: [finalMirror],
            serverSnapshot: afterServer,
            verifiedGrantSum: 115,
            hasReceivedGrantSnapshot: true
        )
        #expect(after.openProvisionalXp == 0)
        #expect(after.displayedTotalXp == 115)
    }
}
