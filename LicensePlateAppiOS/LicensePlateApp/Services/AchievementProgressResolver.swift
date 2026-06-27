//
//  AchievementProgressResolver.swift
//  LicensePlateApp
//
//  Pure catalog-driven achievement progress (read path; no persistence).
//

import Foundation

struct AchievementProgressInputs: Equatable, Sendable {
    var progression: UserProgressionEffectiveTotals?
    var lifetimeStats: UserLifetimeStats?
    var isFamilyMember: Bool
    var isRoyale: Bool
    var isFounder: Bool
}

enum AchievementProgressResolver {

    static func statuses(
        for achievements: [ProgressionCatalogAchievement],
        inputs: AchievementProgressInputs
    ) -> [String: AchievementStatus] {
        Dictionary(uniqueKeysWithValues: achievements.map { entry in
            (entry.id, status(for: entry, inputs: inputs))
        })
    }

    private static func status(
        for entry: ProgressionCatalogAchievement,
        inputs: AchievementProgressInputs
    ) -> AchievementStatus {
        let evaluation = evaluate(entry: entry, inputs: inputs)
        return AchievementStatus(
            isUnlocked: evaluation.unlocked,
            progress: evaluation.progress,
            unlockedDate: nil
        )
    }

    private static func evaluate(
        entry: ProgressionCatalogAchievement,
        inputs: AchievementProgressInputs
    ) -> (progress: Int, unlocked: Bool) {
        switch entry.evaluator {
        case .everCompetitiveFirstPlace:
            let progress = inputs.progression?.everCompetitiveFirstPlace == true ? 1 : 0
            return (progress, progress >= entry.goal)

        case .acceptedRegionCount:
            let count = max(0, inputs.progression?.acceptedRegionFindCount ?? 0)
            return (count, count >= entry.goal)

        case .totalDiscoveries:
            let count = max(0, inputs.lifetimeStats?.totalDiscoveries ?? 0)
            return (count, count >= entry.goal)

        case .winStreak, .flawless:
            return (0, false)

        case .completedTrips:
            let count = max(0, inputs.lifetimeStats?.totalCompletedTrips ?? 0)
            return (count, count >= entry.goal)

        case .familyMember:
            let progress = inputs.isFamilyMember ? 1 : 0
            return (progress, progress >= entry.goal)

        case .competitiveWins:
            let count = max(0, inputs.progression?.competitiveFirstPlaceFinishes ?? 0)
            return (count, count >= entry.goal)

        case .royaleMember:
            let progress = inputs.isRoyale ? 1 : 0
            return (progress, progress >= entry.goal)

        case .founder:
            let progress = inputs.isFounder ? 1 : 0
            return (progress, progress >= entry.goal)
        }
    }
}
