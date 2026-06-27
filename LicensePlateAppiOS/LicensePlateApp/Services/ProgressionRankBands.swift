//
//  ProgressionRankBands.swift
//  LicensePlateApp
//
//  Client-side visual banding.
//

import Foundation

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

    /// Fraction of one band used to show pending overlay (capped).
    static func pendingOverlayFraction(
        pendingXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Double {
        let bandSize = max(1, presentation.visualBandSize)
        let p = max(0, pendingXp)
        return min(Double(p), Double(bandSize)) / Double(bandSize)
    }
}
