//
//  LifetimeStatsPendingSyncState.swift
//  LicensePlateApp
//
//  Pure helper for “pending server sync” UX (local gameplay vs cloud aggregate).
//

import Foundation

enum LifetimeStatsPendingSyncState {
    /// True when UI should show the pending-sync affordance while still showing local fallback numbers.
    static func shouldShowPending(
        isAwaitingServerAfterLocalTripEnd: Bool,
        local: UserLifetimeStats?,
        serverDocumentUpdatedAt: Date?
    ) -> Bool {
        if isAwaitingServerAfterLocalTripEnd {
            return true
        }
        guard let local, let serverDocumentUpdatedAt else {
            return false
        }
        return local.lastComputedAt > serverDocumentUpdatedAt.addingTimeInterval(1.0)
    }
}
