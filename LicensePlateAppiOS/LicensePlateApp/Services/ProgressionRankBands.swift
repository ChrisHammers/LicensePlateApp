//
//  ProgressionRankBands.swift
//  LicensePlateApp
//
//  Rank-ladder segment progress shared by XP toast and profile pending overlay.
//

import Foundation

/// Before/after progress within one rank segment (toast + profile parity).
struct RankSegmentProgress: Equatable, Sendable {
    /// Progress at `xpBefore` within the segment chosen from `xpAfter` (0...1).
    var progressBefore: Double
    /// Progress at `xpAfter` within the same segment (0...1).
    var progressAfter: Double
    /// Absolute XP past the end of the rank after the pre-burst current rank (0 if none).
    var pendingXpBeyondNextRank: Int
    /// True when pending crosses exactly one rank boundary (into next rank only).
    var crossesIntoNextRankOnly: Bool

    var pendingDelta: Double { max(0, progressAfter - progressBefore) }
    var showsBeyondNextRankCaption: Bool { pendingXpBeyondNextRank > 0 }
}

/// Additive fill for profile rank progress: synced + pending within the toast rank segment.
struct ProjectedBandFill: Equatable, Sendable {
    /// Synced XP progress within the current rank segment (0...1).
    var syncedFractionInCurrentBand: Double
    /// Pending XP delta within the same segment (0...1).
    var pendingFractionInCurrentBand: Double
    /// Always 0 — secondary visual-band bar removed; kept for Equatable call-site stability.
    var pendingFractionInNextBand: Double
    /// Pending XP beyond the next rank (absolute XP, not a fraction).
    var pendingXpBeyondNextBand: Int
    /// Pending crosses into the next rank only (caption; no second bar).
    var crossesIntoNextRankOnly: Bool

    var showsNextBandBar: Bool { false }
    var showsBeyondNextBandCaption: Bool { pendingXpBeyondNextBand > 0 }
    var showsNextRankCaption: Bool { crossesIntoNextRankOnly && pendingXpBeyondNextBand == 0 }
}

enum ProgressionRankBands {

    /// Toast/profile shared segment math: segment is chosen from `xpAfter` (same as XP gain toast).
    static func rankSegmentProgress(
        xpBefore: Int,
        xpAfter: Int,
        ladder: RankLadder
    ) -> RankSegmentProgress {
        guard !ladder.ranks.isEmpty else {
            return RankSegmentProgress(
                progressBefore: 0,
                progressAfter: 0,
                pendingXpBeyondNextRank: 0,
                crossesIntoNextRankOnly: false
            )
        }

        let before = max(0, xpBefore)
        let after = max(0, xpAfter)
        let currentAfter = ladder.currentRank(xp: after)
        let nextAfter = ladder.nextRank(xp: after)
        let segmentStart = currentAfter.xpRequired
        let segmentEnd = nextAfter?.xpRequired ?? currentAfter.xpRequired

        let beforeLevel = ladder.currentRank(xp: before).level
        let afterLevel = currentAfter.level
        let ranksCrossed = max(0, afterLevel - beforeLevel)

        return RankSegmentProgress(
            progressBefore: progressInSegment(xp: before, start: segmentStart, end: segmentEnd),
            progressAfter: progressInSegment(xp: after, start: segmentStart, end: segmentEnd),
            pendingXpBeyondNextRank: xpBeyondNextRank(xpBefore: before, xpAfter: after, ladder: ladder),
            crossesIntoNextRankOnly: ranksCrossed == 1
        )
    }

    static func progressInSegment(xp: Int, start: Int, end: Int) -> Double {
        guard end > start else { return 1 }
        return min(1, max(0, Double(xp - start) / Double(end - start)))
    }

    /// Additive pending fill using RankLadder spans (matches `XpGainToastRankBandBuilder`).
    static func projectedBandFill(
        serverXp: Int,
        pendingXp: Int,
        catalog: ProgressionCatalog = ProgressionCatalogProvider.shared.current
    ) -> ProjectedBandFill {
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        let pending = max(0, pendingXp)
        let before = max(0, serverXp)
        let after = before + pending
        let segment = rankSegmentProgress(xpBefore: before, xpAfter: after, ladder: ladder)

        return ProjectedBandFill(
            syncedFractionInCurrentBand: segment.progressBefore,
            pendingFractionInCurrentBand: segment.pendingDelta,
            pendingFractionInNextBand: 0,
            pendingXpBeyondNextBand: segment.pendingXpBeyondNextRank,
            crossesIntoNextRankOnly: segment.crossesIntoNextRankOnly
        )
    }

    /// Legacy modulo helpers (visualBandSize). Prefer `rankSegmentProgress` / `projectedBandFill` for UI.
    static func progressInCurrentBand(
        totalXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Double {
        let bandSize = max(1, presentation.visualBandSize)
        let m = max(totalXp, 0)
        let mod = m % bandSize
        return Double(mod) / Double(bandSize)
    }

    static func roomInCurrentBand(
        serverXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Int {
        let bandSize = max(1, presentation.visualBandSize)
        let m = max(serverXp, 0)
        let used = m % bandSize
        return bandSize - used
    }

    static func pendingOverlayFraction(
        pendingXp: Int,
        presentation: ProgressionPresentationRewards = ProgressionRewardsConfigProvider.shared.current.presentation
    ) -> Double {
        let bandSize = max(1, presentation.visualBandSize)
        let p = max(0, pendingXp)
        return min(Double(p), Double(bandSize)) / Double(bandSize)
    }

    /// XP past the start of the rank after "next" from `xpBefore` (overflow past next rank).
    private static func xpBeyondNextRank(xpBefore: Int, xpAfter: Int, ladder: RankLadder) -> Int {
        guard let next = ladder.nextRank(xp: xpBefore) else { return 0 }
        guard let afterNext = ladder.nextRank(xp: next.xpRequired) else { return 0 }
        return max(0, xpAfter - afterNext.xpRequired)
    }
}
