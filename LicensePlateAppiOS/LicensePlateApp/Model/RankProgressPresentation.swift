//
//  RankProgressPresentation.swift
//  LicensePlateApp
//
//  Pure rules for rank celebration vs provisional XP.
//  Offline play may celebrate from provisional totals; clawback UX handles rare rejects.
//

import Foundation

enum RankProgressPresentation {
    /// True when displayed XP (server + open provisional) crosses `tierBoundary` upward.
    static func shouldCelebrateTierUnlock(displayedXp: Int, previousDisplayedXp: Int, tierBoundary: Int) -> Bool {
        displayedXp >= tierBoundary && previousDisplayedXp < tierBoundary
    }

    /// True when server XP alone crosses the boundary (confirmed unlock).
    static func shouldCelebrateTierUnlock(serverXp: Int, previousServerXp: Int, tierBoundary: Int) -> Bool {
        serverXp >= tierBoundary && previousServerXp < tierBoundary
    }

    /// True when combined server+pending would cross the boundary but server alone has not.
    static func wouldCrossBoundaryFromPendingOnly(serverXp: Int, pendingXp: Int, tierBoundary: Int) -> Bool {
        serverXp < tierBoundary && (serverXp + pendingXp) >= tierBoundary
    }
}
