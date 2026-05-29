//
//  ReturnStreakService.swift
//  LicensePlateApp
//
//  Step 18 — Lightweight return streak, scoped to account/app return state.
//

import Foundation

struct ReturnStreakState: Equatable {
    let currentStreak: Int
    let lastReturnDay: Date?
}

@MainActor
final class ReturnStreakService {
    static let shared = ReturnStreakService(remoteConfig: RemoteConfigService.shared)

    private enum DefaultsKey {
        static let currentStreak = "returnStreak.currentStreak"
        static let lastReturnDay = "returnStreak.lastReturnDay"
    }

    private let remoteConfig: RemoteConfigValueProviding
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(
        remoteConfig: RemoteConfigValueProviding,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.remoteConfig = remoteConfig
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    func recordAppReturnIfNeeded() -> ReturnStreakState {
        guard remoteConfig.bool(for: .returnStreakEnabled) else {
            AnalyticsService.shared.log(.returnStreakReset(reason: "remote_config_disabled"))
            return currentState
        }

        let today = calendar.startOfDay(for: now())
        guard let lastDay = defaults.object(forKey: DefaultsKey.lastReturnDay) as? Date else {
            defaults.set(1, forKey: DefaultsKey.currentStreak)
            defaults.set(today, forKey: DefaultsKey.lastReturnDay)
            AnalyticsService.shared.log(.returnStreakUpdated(currentStreak: 1, reason: "first_return"))
            return currentState
        }

        if calendar.isDate(lastDay, inSameDayAs: today) {
            return currentState
        }

        let previousDay = calendar.date(byAdding: .day, value: -1, to: today)
        if let previousDay, calendar.isDate(lastDay, inSameDayAs: previousDay) {
            let nextStreak = max(1, defaults.integer(forKey: DefaultsKey.currentStreak) + 1)
            defaults.set(nextStreak, forKey: DefaultsKey.currentStreak)
            defaults.set(today, forKey: DefaultsKey.lastReturnDay)
            AnalyticsService.shared.log(.returnStreakUpdated(currentStreak: nextStreak, reason: "consecutive_return"))
        } else {
            defaults.set(1, forKey: DefaultsKey.currentStreak)
            defaults.set(today, forKey: DefaultsKey.lastReturnDay)
            AnalyticsService.shared.log(.returnStreakReset(reason: "missed_day"))
            AnalyticsService.shared.log(.returnStreakUpdated(currentStreak: 1, reason: "reset_return"))
        }

        return currentState
    }

    var currentState: ReturnStreakState {
        ReturnStreakState(
            currentStreak: defaults.integer(forKey: DefaultsKey.currentStreak),
            lastReturnDay: defaults.object(forKey: DefaultsKey.lastReturnDay) as? Date
        )
    }
}
