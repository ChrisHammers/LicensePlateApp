//
//  AchievementUnlockTransitionDetector.swift
//  LicensePlateApp
//
//  Pure diff detection for achievement unlocks and rank-ups.
//

import Foundation

struct AchievementProgressSnapshot: Equatable, Sendable {
    var statuses: [String: AchievementStatus]
    var rankLevel: Int
    var totalXp: Int
}

enum AchievementUnlockTransitionDetector {

    /// Achievement ids that transitioned from locked to unlocked.
    static func newlyUnlockedAchievementIds(
        previous: [String: AchievementStatus]?,
        next: [String: AchievementStatus]
    ) -> [String] {
        guard let previous else { return [] }
        return next.compactMap { id, status in
            guard status.isUnlocked else { return nil }
            let wasUnlocked = previous[id]?.isUnlocked ?? false
            return wasUnlocked ? nil : id
        }
        .sorted()
    }

    /// New rank level when `nextLevel` strictly increased; nil if no rank-up.
    static func rankUpLevel(previous: Int?, nextLevel: Int) -> Int? {
        guard let previous else { return nil }
        guard nextLevel > previous else { return nil }
        return nextLevel
    }
}

enum AchievementProgressSnapshotBuilder {

    @MainActor
    static func build(
        user: AppUser,
        lifetimeStats: UserLifetimeStats?,
        totalXp: Int,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        userProgressionService: UserProgressionService = .shared,
        entitlementService: EntitlementService = .shared,
        persistedRecords: [String: UserAchievementRecord] = [:]
    ) -> AchievementProgressSnapshot {
        let catalog = catalogProvider.current
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalog)
        let xp = max(0, totalXp)
        let entitlement = entitlementService.entitlementState(for: user)
        let inputs = AchievementProgressInputs(
            progression: userProgressionService.effectiveTotals,
            lifetimeStats: lifetimeStats,
            isFamilyMember: user.activeFamilyId != nil || user.wasEverInFamily,
            isRoyale: entitlement.effectiveTier >= .royale,
            isFounder: entitlement.hasTag("founder")
        )
        let computed = AchievementProgressResolver.statuses(
            for: catalog.visibleAchievements,
            inputs: inputs
        )
        let statuses = AchievementProgressPersistence.applyPersistedRecords(
            statuses: computed,
            persisted: persistedRecords
        )
        return AchievementProgressSnapshot(
            statuses: statuses,
            rankLevel: ladder.currentRank(xp: xp).level,
            totalXp: xp
        )
    }
}
