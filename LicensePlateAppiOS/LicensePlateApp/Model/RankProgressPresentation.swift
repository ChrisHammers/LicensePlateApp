//
//  RankProgressPresentation.swift
//  LicensePlateApp
//
//  Pure rules: permanent unlock / celebration must not follow ledger provisional alone (Step XP 03).
//

import Foundation

enum RankProgressPresentation {
    /// True when **server** XP alone crosses `tierBoundary` upward (safe for unlock UI).
    static func shouldCelebrateTierUnlock(serverXp: Int, previousServerXp: Int, tierBoundary: Int) -> Bool {
        serverXp >= tierBoundary && previousServerXp < tierBoundary
    }

    /// True when combined server+pending would cross the boundary but server alone has not — **do not** treat as unlocked.
    static func wouldCrossBoundaryFromPendingOnly(serverXp: Int, pendingXp: Int, tierBoundary: Int) -> Bool {
        serverXp < tierBoundary && (serverXp + pendingXp) >= tierBoundary
    }
}
