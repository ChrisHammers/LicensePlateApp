//
//  ReturnStreakXpScopeKey.swift
//  LicensePlateApp
//
//  Shared scope key for return-streak daily XP (mirrors Cloud Functions).
//

import Foundation

enum ReturnStreakXpScopeKey {
    static func daily(userId: String, dayKey: String) -> String {
        "return_streak_daily|v1|\(userId)|\(dayKey)"
    }
}
