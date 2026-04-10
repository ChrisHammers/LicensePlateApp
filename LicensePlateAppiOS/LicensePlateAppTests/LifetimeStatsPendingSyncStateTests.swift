//
//  LifetimeStatsPendingSyncStateTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LifetimeStatsPendingSyncStateTests {

    @Test func pendingWhenAwaitingServerFlag() {
        let local = UserLifetimeStats(
            totalCompletedTrips: 1,
            totalGamesPlayed: 1,
            totalDiscoveries: 0,
            totalWeightedScore: 0,
            familyOnlyTripsCount: 0,
            lastComputedAt: Date()
        )
        let p = LifetimeStatsPendingSyncState.shouldShowPending(
            isAwaitingServerAfterLocalTripEnd: true,
            local: local,
            serverDocumentUpdatedAt: Date()
        )
        #expect(p == true)
    }

    @Test func pendingWhenLocalNewerThanServerDoc() {
        let serverDate = Date(timeIntervalSince1970: 1_000)
        let local = UserLifetimeStats(
            totalCompletedTrips: 2,
            totalGamesPlayed: 2,
            totalDiscoveries: 0,
            totalWeightedScore: 0,
            familyOnlyTripsCount: 0,
            lastComputedAt: serverDate.addingTimeInterval(10)
        )
        let p = LifetimeStatsPendingSyncState.shouldShowPending(
            isAwaitingServerAfterLocalTripEnd: false,
            local: local,
            serverDocumentUpdatedAt: serverDate
        )
        #expect(p == true)
    }

    @Test func notPendingWhenServerFreshEnough() {
        let localDate = Date(timeIntervalSince1970: 2_000)
        let serverDate = localDate.addingTimeInterval(5)
        let local = UserLifetimeStats(
            totalCompletedTrips: 1,
            totalGamesPlayed: 1,
            totalDiscoveries: 0,
            totalWeightedScore: 0,
            familyOnlyTripsCount: 0,
            lastComputedAt: localDate
        )
        let p = LifetimeStatsPendingSyncState.shouldShowPending(
            isAwaitingServerAfterLocalTripEnd: false,
            local: local,
            serverDocumentUpdatedAt: serverDate
        )
        #expect(p == false)
    }
}
