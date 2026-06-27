//
//  ProgressionCatalogProjection.swift
//  LicensePlateApp
//
//  Maps bundled catalog entries into UI-facing achievement/rank models.
//

import Foundation

enum ProgressionCatalogProjection {

    static func achievements(from catalog: ProgressionCatalog) -> [Achievement] {
        catalog.visibleAchievements.map { achievement(from: $0) }
    }

    static func achievement(from entry: ProgressionCatalogAchievement) -> Achievement {
        Achievement(
            id: entry.id,
            title: entry.titleKey.localized,
            detail: entry.detailKey.localized,
            icon: entry.icon,
            rarity: licenseRarity(from: entry.rarity),
            category: achievementCategory(from: entry.category),
            goal: entry.goal,
            xpReward: entry.xpReward
        )
    }

    static func rankLadder(from catalog: ProgressionCatalog) -> RankLadder {
        let ranks = catalog.rankLadder.ranks
            .sorted { $0.level < $1.level }
            .map { rank(from: $0) }
        return RankLadder(ranks: ranks)
    }

    static func rank(from entry: ProgressionCatalogRank) -> Rank {
        Rank(
            level: entry.level,
            title: entry.titleKey.localized,
            xpRequired: entry.xpRequired,
            unlocks: entry.unlocks.map { rankUnlock(from: $0) }
        )
    }

    private static func rankUnlock(from entry: ProgressionCatalogRankUnlock) -> RankUnlock {
        RankUnlock(
            title: entry.titleKey.localized,
            icon: entry.icon,
            kind: rankUnlockKind(from: entry.kind)
        )
    }

    private static func licenseRarity(from rarity: ProgressionCatalogAchievementRarity) -> LicenseRarity {
        switch rarity {
        case .common: return .common
        case .rare: return .rare
        case .epic: return .epic
        case .legendary: return .legendary
        case .mythic: return .mythic
        }
    }

    private static func achievementCategory(from category: ProgressionCatalogAchievementCategory) -> AchievementCategory {
        switch category {
        case .exploration: return .exploration
        case .collection: return .collection
        case .competition: return .competition
        case .milestones: return .milestones
        case .social: return .social
        }
    }

    private static func rankUnlockKind(from kind: ProgressionCatalogRankUnlockKind) -> RankUnlock.Kind {
        switch kind {
        case .cosmetic: return .cosmetic
        case .feature: return .feature
        case .badge: return .badge
        case .title: return .title
        }
    }
}

extension ProgressionCatalogAchievementCategory {
    var localizationKey: String { "achievement.category.\(rawValue)" }
    var localizedTitle: String { localizationKey.localized }
}
