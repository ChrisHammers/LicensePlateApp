//
//  ProgressionRankBands.swift
//  LicensePlateApp
//
//  Client-side visual banding.
//

import Foundation

/// Additive fill for profile rank-band bars: synced progress + pending in the current band,
/// with optional spill into the next band (capped) and remainder beyond.
struct ProjectedBandFill: Equatable, Sendable {
    /// Synced XP progress within the current band (0...1).
    var syncedFractionInCurrentBand: Double
    /// Pending XP that still fits in the current band after synced fill, as a fraction of one band (0...1).
    var pendingFractionInCurrentBand: Double
    /// Pending XP that spills into the next band only, as a fraction of one band (0...1).
    var pendingFractionInNextBand: Double
    /// Pending XP beyond the next band (absolute XP, not a fraction).
    var pendingXpBeyondNextBand: Int

    var showsNextBandBar: Bool { pendingFractionInNextBand > 0 }
    var showsBeyondNextBandCaption: Bool { pendingXpBeyondNextBand > 0 }
}

enum ProgressionRankBands {

    static func progressInCurrentBand(
        totalXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Double {
        let bandSize = max(1, presentation.visualBandSize)
        let m = max(totalXp, 0)
        let mod = m % bandSize
        return Double(mod) / Double(bandSize)
    }

    /// XP remaining in the current visual band before the next boundary.
    static func roomInCurrentBand(
        serverXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Int {
        let bandSize = max(1, presentation.visualBandSize)
        let m = max(serverXp, 0)
        let used = m % bandSize
        return bandSize - used
    }

    /// Additive pending fill relative to synced position in the current band.
    static func projectedBandFill(
        serverXp: Int,
        pendingXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> ProjectedBandFill {
        let bandSize = max(1, presentation.visualBandSize)
        let pending = max(0, pendingXp)
        let syncedFraction = progressInCurrentBand(totalXp: serverXp, presentation: presentation)
        let room = roomInCurrentBand(serverXp: serverXp, presentation: presentation)

        let inCurrent = min(pending, room)
        let afterCurrent = pending - inCurrent
        let inNext = min(afterCurrent, bandSize)
        let beyondNext = afterCurrent - inNext

        return ProjectedBandFill(
            syncedFractionInCurrentBand: syncedFraction,
            pendingFractionInCurrentBand: Double(inCurrent) / Double(bandSize),
            pendingFractionInNextBand: Double(inNext) / Double(bandSize),
            pendingXpBeyondNextBand: beyondNext
        )
    }

    /// Fraction of one band used to show pending overlay (capped). Legacy helper for tests.
    static func pendingOverlayFraction(
        pendingXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Double {
        let bandSize = max(1, presentation.visualBandSize)
        let p = max(0, pendingXp)
        return min(Double(p), Double(bandSize)) / Double(bandSize)
    }
}
