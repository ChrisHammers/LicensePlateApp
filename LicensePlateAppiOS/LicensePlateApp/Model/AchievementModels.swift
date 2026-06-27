//
//  AchievementModels.swift
//  RoadTrip Royale
//
//  Shared data for the achievement list, rank progression, and reward popup.
//  Reuses `LicenseRarity` (see LicenseLocker.swift) for tinting and titles.
//
//  Ownership/progress is the host app's data: the views take the catalog plus
//  the player's status (unlocked + progress) and render over it.
//

import SwiftUI

// MARK: - Achievements

enum AchievementCategory: String, CaseIterable, Identifiable {
    case exploration = "Exploration"
    case collection  = "Collection"
    case competition = "Competition"
    case milestones  = "Milestones"
    case social      = "Social"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .exploration: return "map.fill"
        case .collection:  return "rectangle.stack.fill"
        case .competition: return "trophy.fill"
        case .milestones:  return "flag.checkered"
        case .social:      return "person.2.fill"
        }
    }

    var localizedTitle: String {
        switch self {
        case .exploration: return "achievement.category.exploration".localized
        case .collection: return "achievement.category.collection".localized
        case .competition: return "achievement.category.competition".localized
        case .milestones: return "achievement.category.milestones".localized
        case .social: return "achievement.category.social".localized
        }
    }
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String          // what it is / how to unlock
    let icon: String            // SF Symbol
    let rarity: LicenseRarity
    let category: AchievementCategory
    let goal: Int               // 1 for a simple yes/no achievement
    let xpReward: Int

    init(id: String, title: String, detail: String, icon: String,
         rarity: LicenseRarity, category: AchievementCategory,
         goal: Int = 1, xpReward: Int) {
        self.id = id; self.title = title; self.detail = detail; self.icon = icon
        self.rarity = rarity; self.category = category; self.goal = goal; self.xpReward = xpReward
    }
}

/// Player-specific state for an achievement. Missing entry == locked, no progress.
struct AchievementStatus: Equatable {
    var isUnlocked: Bool
    var progress: Int
    var unlockedDate: Date?

    init(isUnlocked: Bool = false, progress: Int = 0, unlockedDate: Date? = nil) {
        self.isUnlocked = isUnlocked; self.progress = progress; self.unlockedDate = unlockedDate
    }

    static let locked = AchievementStatus()
}

extension Achievement {
    var hasMeter: Bool { goal > 1 }

    static let catalog: [Achievement] = [
        Achievement(id: "first_win", title: "First Victory",
                    detail: "Win your first game.", icon: "checkmark.seal.fill",
                    rarity: .common, category: .competition, xpReward: 100),
        Achievement(id: "explorer_10", title: "Getting Started",
                    detail: "Spot plates from 10 different states or provinces.",
                    icon: "signpost.right.fill", rarity: .common, category: .exploration,
                    goal: 10, xpReward: 200),
        Achievement(id: "plates_100", title: "Plate Spotter",
                    detail: "Find 100 license plates in total.", icon: "rectangle.on.rectangle",
                    rarity: .common, category: .collection, goal: 100, xpReward: 250),
        Achievement(id: "streak_5", title: "On a Roll",
                    detail: "Win 5 games in a row.", icon: "flame.fill",
                    rarity: .rare, category: .competition, goal: 5, xpReward: 500),
        Achievement(id: "trips_10", title: "Frequent Traveler",
                    detail: "Complete 10 road trips.", icon: "road.lanes",
                    rarity: .rare, category: .milestones, goal: 10, xpReward: 400),
        Achievement(id: "family", title: "Family Road Trip",
                    detail: "Join or create a family.", icon: "person.3.fill",
                    rarity: .rare, category: .social, xpReward: 300),
        Achievement(id: "plates_1000", title: "Plate Hoarder",
                    detail: "Find 1,000 license plates in total.", icon: "square.stack.3d.up.fill",
                    rarity: .epic, category: .collection, goal: 1000, xpReward: 2000),
        Achievement(id: "wins_100", title: "Champion",
                    detail: "Win 100 games.", icon: "trophy.fill",
                    rarity: .epic, category: .competition, goal: 100, xpReward: 2500),
        Achievement(id: "trips_50", title: "Road Veteran",
                    detail: "Complete 50 road trips.", icon: "car.2.fill",
                    rarity: .epic, category: .milestones, goal: 50, xpReward: 1500),
        Achievement(id: "royale", title: "Living Royale",
                    detail: "Become a Royale member.", icon: "crown.fill",
                    rarity: .epic, category: .social, xpReward: 0),
        Achievement(id: "coast_to_coast", title: "Coast to Coast",
                    detail: "Find plates from all 63 states and provinces.", icon: "map.fill",
                    rarity: .legendary, category: .exploration, goal: 63, xpReward: 5000),
        Achievement(id: "flawless", title: "Flawless",
                    detail: "Finish a game without a single miss.", icon: "sparkles",
                    rarity: .legendary, category: .competition, xpReward: 1500),
        Achievement(id: "founder", title: "Founder",
                    detail: "Play during the launch season.", icon: "star.circle.fill",
                    rarity: .mythic, category: .milestones, xpReward: 0)
    ]

    /// Demo statuses: a mix of unlocked, in-progress, and locked.
    static func sampleStatuses() -> [String: AchievementStatus] {
        [
            "first_win":     .init(isUnlocked: true, progress: 1, unlockedDate: .now.addingTimeInterval(-86_400 * 30)),
            "explorer_10":   .init(isUnlocked: true, progress: 10, unlockedDate: .now.addingTimeInterval(-86_400 * 22)),
            "plates_100":    .init(isUnlocked: true, progress: 100, unlockedDate: .now.addingTimeInterval(-86_400 * 15)),
            "streak_5":      .init(isUnlocked: true, progress: 5, unlockedDate: .now.addingTimeInterval(-86_400 * 9)),
            "family":        .init(isUnlocked: true, progress: 1, unlockedDate: .now.addingTimeInterval(-86_400 * 5)),
            "royale":        .init(isUnlocked: true, progress: 1, unlockedDate: .now.addingTimeInterval(-86_400 * 2)),
            "plates_1000":   .init(isUnlocked: false, progress: 1240),   // already past goal-style big number, but flagged below
            "wins_100":      .init(isUnlocked: false, progress: 121),
            "trips_10":      .init(isUnlocked: true, progress: 10, unlockedDate: .now.addingTimeInterval(-86_400 * 12)),
            "trips_50":      .init(isUnlocked: false, progress: 36),
            "coast_to_coast":.init(isUnlocked: false, progress: 48),
            "flawless":      .init(isUnlocked: false, progress: 0)
            // "founder" intentionally omitted -> fully locked
        ]
    }
}

// MARK: - Ranks

struct RankUnlock: Identifiable {
    enum Kind { case cosmetic, feature, badge, title }
    let id = UUID()
    let title: String
    let icon: String
    let kind: Kind
}

struct Rank: Identifiable {
    let level: Int
    let title: String
    let xpRequired: Int          // cumulative XP to reach this rank
    let unlocks: [RankUnlock]

    var id: Int { level }

    static func tier(_ level: Int) -> Int {
        switch level {
        case ..<3:  return 0   // bronze
        case ..<5:  return 1   // silver
        case ..<7:  return 2   // gold
        case ..<9:  return 3   // platinum
        default:    return 4   // diamond
        }
    }

    var accent: Color {
        switch Rank.tier(level) {
        case 0:  return Color(red: 0.72, green: 0.50, blue: 0.30)
        case 1:  return Color(red: 0.66, green: 0.69, blue: 0.74)
        case 2:  return Color(red: 0.85, green: 0.65, blue: 0.13)
        case 3:  return Color(red: 0.40, green: 0.78, blue: 0.86)
        default: return Color(red: 0.60, green: 0.40, blue: 0.88)
        }
    }

    var icon: String {
        switch Rank.tier(level) {
        case 0:  return "car.fill"
        case 1:  return "car.2.fill"
        case 2:  return "flame.fill"
        case 3:  return "bolt.fill"
        default: return "crown.fill"
        }
    }
}

struct RankLadder {
    let ranks: [Rank]

    func currentRank(xp: Int) -> Rank {
        ranks.last { $0.xpRequired <= xp } ?? ranks[0]
    }

    func nextRank(xp: Int) -> Rank? {
        ranks.first { $0.xpRequired > xp }
    }

    /// Fraction through the current rank toward the next (0...1).
    func progress(xp: Int) -> Double {
        guard let next = nextRank(xp: xp) else { return 1 }
        let cur = currentRank(xp: xp)
        let span = Double(next.xpRequired - cur.xpRequired)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(xp - cur.xpRequired) / span))
    }

    static let standard = RankLadder(ranks: [
        Rank(level: 1, title: "Rookie Rider", xpRequired: 0,
             unlocks: [RankUnlock(title: "Standard License", icon: "creditcard.fill", kind: .cosmetic)]),
        Rank(level: 2, title: "Road Tripper", xpRequired: 1_000,
             unlocks: [RankUnlock(title: "Custom Plate Name", icon: "textformat", kind: .feature)]),
        Rank(level: 3, title: "Navigator", xpRequired: 3_000,
             unlocks: [RankUnlock(title: "Navigator Badge", icon: "location.north.circle.fill", kind: .badge)]),
        Rank(level: 4, title: "Trailblazer", xpRequired: 7_000,
             unlocks: [RankUnlock(title: "Carbon Edition", icon: "square.grid.3x3.fill", kind: .cosmetic)]),
        Rank(level: 5, title: "Pathfinder", xpRequired: 15_000,
             unlocks: [RankUnlock(title: "Family Invites", icon: "person.3.fill", kind: .feature),
                       RankUnlock(title: "Pathfinder Badge", icon: "rosette", kind: .badge)]),
        Rank(level: 6, title: "Road Warrior", xpRequired: 30_000,
             unlocks: [RankUnlock(title: "Gold Foil", icon: "sparkles", kind: .cosmetic)]),
        Rank(level: 7, title: "Highway Legend", xpRequired: 55_000,
             unlocks: [RankUnlock(title: "Legend Title", icon: "text.badge.star", kind: .title),
                       RankUnlock(title: "Legend Badge", icon: "medal.fill", kind: .badge)]),
        Rank(level: 8, title: "Route Master", xpRequired: 90_000,
             unlocks: [RankUnlock(title: "Platinum Foil", icon: "diamond.fill", kind: .cosmetic)]),
        Rank(level: 9, title: "Asphalt Royalty", xpRequired: 140_000,
             unlocks: [RankUnlock(title: "Midnight Drive", icon: "moon.stars.fill", kind: .cosmetic)]),
        Rank(level: 10, title: "Grand Voyager", xpRequired: 220_000,
             unlocks: [RankUnlock(title: "Prestige Mode", icon: "infinity", kind: .feature),
                       RankUnlock(title: "Founder Frame", icon: "crown.fill", kind: .cosmetic)])
    ])
}
