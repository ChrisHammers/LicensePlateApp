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
}
