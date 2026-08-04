//
//  ProgressionXpDriftAfterSyncReporterTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionXpDriftEvaluatorTests {

    @Test func noDriftWhenSynced() {
        let snapshot = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: ["e1"],
            appliedProgressionScopeKeys: []
        )
        let effective = UserProgressionEffectiveTotals(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            hasPendingLocalProgression: false
        )
        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: [],
            serverSnapshot: snapshot,
            effectiveTotals: effective,
            verifiedGrantSum: 100,
            hasReceivedGrantSnapshot: true
        )
        #expect(!drift.hasAnyDrift)
        #expect(!drift.hasOpenProvisional)
        #expect(!drift.hasPendingLocalProgression)
        #expect(!drift.grantLedgerMismatch)
    }

    @Test func flagsOpenProvisional() {
        let sessionId = UUID()
        let gameId = UUID()
        let provisional = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "local-1",
            sourceEventType: "region_found",
            itemId: "us-ca",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: "key-1"
        )
        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: [provisional],
            serverSnapshot: .empty,
            effectiveTotals: nil,
            verifiedGrantSum: 0,
            hasReceivedGrantSnapshot: true
        )
        #expect(drift.hasAnyDrift)
        #expect(drift.hasOpenProvisional)
        #expect(drift.openProvisionalXp == 10)
    }

    @Test func flagsPendingLocalProgression() {
        let effective = UserProgressionEffectiveTotals(
            totalXp: 130,
            acceptedRegionFindCount: 11,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            hasPendingLocalProgression: true
        )
        let snapshot = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: [],
            serverSnapshot: snapshot,
            effectiveTotals: effective,
            verifiedGrantSum: 100,
            hasReceivedGrantSnapshot: true
        )
        #expect(drift.hasAnyDrift)
        #expect(drift.hasPendingLocalProgression)
        #expect(drift.pendingLocalXpDelta == 30)
    }

    @Test func flagsGrantLedgerMismatch() {
        let snapshot = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        let effective = UserProgressionEffectiveTotals(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            hasPendingLocalProgression: false
        )
        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: [],
            serverSnapshot: snapshot,
            effectiveTotals: effective,
            verifiedGrantSum: 80,
            hasReceivedGrantSnapshot: true
        )
        #expect(drift.hasAnyDrift)
        #expect(drift.grantLedgerMismatch)
        #expect(drift.verifiedGrantSum == 80)
    }

    @Test func doesNotFlagGrantMismatchWithoutGrantSnapshot() {
        let snapshot = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 10,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: [],
            appliedProgressionScopeKeys: []
        )
        let drift = ProgressionXpDriftEvaluator.snapshot(
            ledgerEvents: [],
            serverSnapshot: snapshot,
            effectiveTotals: nil,
            verifiedGrantSum: 80,
            hasReceivedGrantSnapshot: false
        )
        #expect(!drift.grantLedgerMismatch)
        #expect(drift.verifiedGrantSum == nil)
    }
}

@MainActor
struct ProgressionXpDriftAnalyticsTests {

    @Test func eventNameAndParameters() {
        let event = AnalyticsService.Event.progressionXpDriftAfterSync(
            openProvisionalXp: 10,
            hasOpenProvisional: true,
            hasPendingLocalProgression: true,
            pendingLocalXpDelta: 15,
            serverTotalXp: 200,
            verifiedGrantSum: 180,
            grantLedgerMismatch: true,
            hasReceivedGrantSnapshot: true,
            progressionTriggerConfirmed: false,
            recentlyAcceptedCount: 2,
            settleWaitMs: 45_000
        )
        #expect(event.name == "progression_xp_drift_after_sync")
        let params = event.parameters
        #expect(params?["open_provisional_xp"] as? Int == 10)
        #expect(params?["has_open_provisional"] as? Bool == true)
        #expect(params?["has_pending_local_progression"] as? Bool == true)
        #expect(params?["pending_local_xp_delta"] as? Int == 15)
        #expect(params?["server_total_xp"] as? Int == 200)
        #expect(params?["verified_grant_sum"] as? Int == 180)
        #expect(params?["grant_ledger_mismatch"] as? Bool == true)
        #expect(params?["has_received_grant_snapshot"] as? Bool == true)
        #expect(params?["progression_trigger_confirmed"] as? Bool == false)
        #expect(params?["recently_accepted_count"] as? Int == 2)
        #expect(params?["settle_wait_ms"] as? Int == 45_000)
    }

    @Test func omitsVerifiedGrantSumWhenNil() {
        let event = AnalyticsService.Event.progressionXpDriftAfterSync(
            openProvisionalXp: 0,
            hasOpenProvisional: false,
            hasPendingLocalProgression: true,
            pendingLocalXpDelta: 5,
            serverTotalXp: 50,
            verifiedGrantSum: nil,
            grantLedgerMismatch: false,
            hasReceivedGrantSnapshot: false,
            progressionTriggerConfirmed: true,
            recentlyAcceptedCount: 1,
            settleWaitMs: 1_200
        )
        #expect(event.parameters?["verified_grant_sum"] == nil)
    }
}
