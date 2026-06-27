//
//  ProgressionCatalogLegacyParity.swift
//  LicensePlateAppTests
//
//  Frozen parity expectations from the original AchievementModels / RankLadder fixtures.
//

import Foundation
@testable import LicensePlateApp

enum ProgressionCatalogLegacyParity {

    struct AchievementExpectation {
        var goal: Int
        var xpReward: Int
        var icon: String
        var rarity: String
        var category: String
    }

    static let achievementCount = 13
    static let visibleAchievementCount = 11
    static let rankCount = 10
    static let coastToCoastGoal = 63

    static let rankXpThresholds: [Int] = [
        0, 1_000, 3_000, 7_000, 15_000, 30_000, 55_000, 90_000, 140_000, 220_000
    ]

    static let achievementExpectations: [String: AchievementExpectation] = [
        "first_win": .init(goal: 1, xpReward: 100, icon: "checkmark.seal.fill", rarity: "common", category: "competition"),
        "explorer_10": .init(goal: 10, xpReward: 200, icon: "signpost.right.fill", rarity: "common", category: "exploration"),
        "plates_100": .init(goal: 100, xpReward: 250, icon: "rectangle.on.rectangle", rarity: "common", category: "collection"),
        "streak_5": .init(goal: 5, xpReward: 500, icon: "flame.fill", rarity: "rare", category: "competition"),
        "trips_10": .init(goal: 10, xpReward: 400, icon: "road.lanes", rarity: "rare", category: "milestones"),
        "family": .init(goal: 1, xpReward: 300, icon: "person.3.fill", rarity: "rare", category: "social"),
        "plates_1000": .init(goal: 1_000, xpReward: 2_000, icon: "square.stack.3d.up.fill", rarity: "epic", category: "collection"),
        "wins_100": .init(goal: 100, xpReward: 2_500, icon: "trophy.fill", rarity: "epic", category: "competition"),
        "trips_50": .init(goal: 50, xpReward: 1_500, icon: "car.2.fill", rarity: "epic", category: "milestones"),
        "royale": .init(goal: 1, xpReward: 0, icon: "crown.fill", rarity: "epic", category: "social"),
        "coast_to_coast": .init(goal: 63, xpReward: 5_000, icon: "map.fill", rarity: "legendary", category: "exploration"),
        "flawless": .init(goal: 1, xpReward: 1_500, icon: "sparkles", rarity: "legendary", category: "competition"),
        "founder": .init(goal: 1, xpReward: 0, icon: "star.circle.fill", rarity: "mythic", category: "milestones"),
    ]
}
