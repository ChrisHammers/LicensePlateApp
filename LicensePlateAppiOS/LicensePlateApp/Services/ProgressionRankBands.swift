//
//  ProgressionRankBands.swift
//  LicensePlateApp
//
//  Client-side visual banding until tier thresholds are shared from backend (Step XP 03).
//

import Foundation

enum ProgressionRankBands {
    /// Modular XP band for progress ring visuals (not authoritative for unlocks).
    static let visualBandSize = 100

    static func progressInCurrentBand(totalXp: Int) -> Double {
        let m = max(totalXp, 0)
        let mod = m % visualBandSize
        return Double(mod) / Double(visualBandSize)
    }

    /// Fraction of one band used to show pending overlay (capped).
    static func pendingOverlayFraction(pendingXp: Int) -> Double {
        let p = max(0, pendingXp)
        return min(Double(p), Double(visualBandSize)) / Double(visualBandSize)
    }
}
