//
//  AchievementProgressPersistence.swift
//  LicensePlateApp
//
//  Merges resolver output with locally persisted unlock rows.
//

import Foundation

enum AchievementProgressPersistence {

    static func applyPersistedRecords(
        statuses: [String: AchievementStatus],
        persisted: [String: UserAchievementRecord]
    ) -> [String: AchievementStatus] {
        guard !persisted.isEmpty else { return statuses }
        var merged = statuses
        for (id, var status) in merged {
            guard status.isUnlocked, let record = persisted[id] else { continue }
            status.progress = max(status.progress, record.lastProgress)
            if !record.isBackfilled {
                status.unlockedDate = record.unlockedAt
            }
            merged[id] = status
        }
        return merged
    }

    static func persistedAchievementIds(_ persisted: [String: UserAchievementRecord]) -> Set<String> {
        Set(persisted.keys)
    }

    static func filterNotYetPersisted(_ achievementIds: [String], persistedIds: Set<String>) -> [String] {
        achievementIds.filter { !persistedIds.contains($0) }
    }
}
