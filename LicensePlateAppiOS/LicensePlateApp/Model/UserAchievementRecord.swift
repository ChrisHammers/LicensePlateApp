//
//  UserAchievementRecord.swift
//  LicensePlateApp
//
//  Domain row for locally persisted achievement unlock state.
//

import Foundation

struct UserAchievementRecord: Equatable, Sendable, Identifiable {
    var userId: String
    var achievementId: String
    var unlockedAt: Date
    var lastProgress: Int
    var isBackfilled: Bool

    var id: String { achievementId }
}
