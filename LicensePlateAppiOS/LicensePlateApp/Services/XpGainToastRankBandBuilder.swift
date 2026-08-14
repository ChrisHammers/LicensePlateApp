//
//  XpGainToastRankBandBuilder.swift
//  LicensePlateApp
//
//  Rank ladder snapshot for the XP toast footer band.
//

import Foundation

struct XpGainToastRankBand: Equatable, Sendable {
    var currentRankLevel: Int
    var currentRankTitle: String
    var currentRankIcon: String
    var nextRankLevel: Int?
    var nextRankTitle: String?
    var nextRankIcon: String?
    var xpToNextRank: Int?
    var burstXpGained: Int
    var progressBeforeBurst: Double
    var progressAfterBurst: Double
    var isMaxRank: Bool
}

enum XpGainToastRankBandBuilder {

    static func build(
        totalXpBeforeBurst: Int,
        burstXpGained: Int,
        catalog: ProgressionCatalog
    ) -> XpGainToastRankBand? {
        guard catalog.presentation.rankProgressionEnabled else { return nil }

        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        guard !ladder.ranks.isEmpty else { return nil }

        let xpBefore = max(0, totalXpBeforeBurst)
        let burst = max(0, burstXpGained)
        let xpAfter = max(0, totalXpBeforeBurst + burst)
        let current = ladder.currentRank(xp: xpAfter)
        let next = ladder.nextRank(xp: xpAfter)
        let isMaxRank = next == nil
        let segment = ProgressionRankBands.rankSegmentProgress(
            xpBefore: xpBefore,
            xpAfter: xpAfter,
            ladder: ladder
        )

        return XpGainToastRankBand(
            currentRankLevel: current.level,
            currentRankTitle: current.title,
            currentRankIcon: current.icon,
            nextRankLevel: next?.level,
            nextRankTitle: next?.title,
            nextRankIcon: next?.icon,
            xpToNextRank: next.map { max(0, $0.xpRequired - xpAfter) },
            burstXpGained: burst,
            progressBeforeBurst: segment.progressBefore,
            progressAfterBurst: segment.progressAfter,
            isMaxRank: isMaxRank
        )
    }
}
