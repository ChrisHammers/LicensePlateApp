//
//  UserAchievementEntity.swift
//  LicensePlateApp
//
//  Local persistence for achievement unlock timestamps and progress (Schema V20+).
//

import Foundation
import SwiftData

@Model
final class UserAchievementEntity {
    @Attribute(.unique) var recordKey: String
    var userId: String
    var achievementId: String
    var unlockedAt: Date
    var lastProgress: Int
    /// True when row was backfilled from pre-existing unlock (no celebration); hide date in UI.
    var isBackfilled: Bool

    init(
        userId: String,
        achievementId: String,
        unlockedAt: Date = .now,
        lastProgress: Int = 0,
        isBackfilled: Bool = false
    ) {
        self.userId = userId
        self.achievementId = achievementId
        self.recordKey = Self.makeRecordKey(userId: userId, achievementId: achievementId)
        self.unlockedAt = unlockedAt
        self.lastProgress = lastProgress
        self.isBackfilled = isBackfilled
    }

    static func makeRecordKey(userId: String, achievementId: String) -> String {
        "\(userId)|\(achievementId)"
    }
}
