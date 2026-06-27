//
//  ReturnStreakService.swift
//  LicensePlateApp
//
//  Daily plate-find streak per user. All day-boundary math lives here.
//
//  Calendar semantics (Phase 1):
//  - Uses injectable Calendar (default Calendar.current): device locale + timezone at evaluation time.
//  - Day boundary: calendar.startOfDay(for: now()).
//  - lastQualifyingDay is stored as an absolute Date (start-of-day instant when qualified).
//  - Comparisons use calendar.isDate(_:inSameDayAs:).
//  - DST / travel: boundaries follow the device calendar; timezone changes may shift perceived days.
//  - Offline: UserDefaults only; idempotent per user per calendar day.
//  - Clock manipulation: local-trust only (no server authority in Phase 1).
//

import Foundation
import Combine

struct ReturnStreakState: Equatable {
    let currentStreak: Int
    let lastQualifyingDay: Date?
}

enum ReturnStreakRecordOutcome: Equatable {
    case disabled
    case noOp(alreadyQualifiedToday: Bool)
    case continued(previousStreak: Int, currentStreak: Int)
    case started(currentStreak: Int)
    case brokenThenStarted(previousStreak: Int)
}

@MainActor
final class ReturnStreakService: ObservableObject {

    static let shared = ReturnStreakService(remoteConfig: RemoteConfigService.shared)

    private enum LegacyDefaultsKey {
        static let currentStreak = "returnStreak.currentStreak"
        static let lastReturnDay = "returnStreak.lastReturnDay"
    }

    private let remoteConfig: RemoteConfigValueProviding
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private(set) var activeUserId: String?
    private(set) var lastRecordOutcome: ReturnStreakRecordOutcome?

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

    func setActiveUserId(_ userId: String?) {
        activeUserId = userId
        if let userId, !userId.isEmpty {
            migrateLegacyDeviceStateIfNeeded(for: userId)
        }
    }

    func consumeLastRecordOutcome() -> ReturnStreakRecordOutcome? {
        defer { lastRecordOutcome = nil }
        return lastRecordOutcome
    }

    func currentState(for userId: String? = nil) -> ReturnStreakState {
        guard let userId = resolvedUserId(userId) else {
            return ReturnStreakState(currentStreak: 0, lastQualifyingDay: nil)
        }
        migrateLegacyDeviceStateIfNeeded(for: userId)
        return ReturnStreakState(
            currentStreak: defaults.integer(forKey: streakKey(userId: userId)),
            lastQualifyingDay: defaults.object(forKey: lastDayKey(userId: userId)) as? Date
        )
    }

    var isEnabled: Bool {
        remoteConfig.bool(for: .returnStreakEnabled)
    }

    var minDisplayStreak: Int {
        max(1, remoteConfig.int(for: .returnStreakMinDisplay))
    }

    var celebrationEnabled: Bool {
        remoteConfig.bool(for: .returnStreakCelebrationEnabled)
    }

    var celebrationMinStreak: Int {
        max(1, remoteConfig.int(for: .returnStreakCelebrationMinStreak))
    }

    /// Records a qualifying plate find for the active user when the event belongs to them.
    @discardableResult
    func handleCommittedActivityEvent(_ event: TripActivityEvent) -> ReturnStreakRecordOutcome {
        guard let userId = activeUserId, !userId.isEmpty else { return .disabled }
        guard event.kind == .regionFound else { return .noOp(alreadyQualifiedToday: false) }
        let participantId = event.payload?[TripActivityEventPayloadKey.participantId]
            ?? event.actorId
            ?? ""
        guard participantId == userId else { return .noOp(alreadyQualifiedToday: false) }
        return recordQualifyingFindIfNeeded(userId: userId)
    }

    @discardableResult
    func recordQualifyingFindIfNeeded(userId: String) -> ReturnStreakRecordOutcome {
        guard remoteConfig.bool(for: .returnStreakEnabled) else {
            lastRecordOutcome = .disabled
            return .disabled
        }

        migrateLegacyDeviceStateIfNeeded(for: userId)

        let today = calendar.startOfDay(for: now())
        let streakKey = streakKey(userId: userId)
        let lastDayKey = lastDayKey(userId: userId)

        if let lastDay = defaults.object(forKey: lastDayKey) as? Date,
           calendar.isDate(lastDay, inSameDayAs: today) {
            let outcome = ReturnStreakRecordOutcome.noOp(alreadyQualifiedToday: true)
            lastRecordOutcome = outcome
            return outcome
        }

        let previousStreak = defaults.integer(forKey: streakKey)
        let outcome: ReturnStreakRecordOutcome

        if defaults.object(forKey: lastDayKey) as? Date == nil {
            defaults.set(1, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: 1, reason: "first"))
            outcome = .started(currentStreak: 1)
        } else if let lastDay = defaults.object(forKey: lastDayKey) as? Date,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(lastDay, inSameDayAs: previousDay) {
            let nextStreak = max(1, previousStreak + 1)
            defaults.set(nextStreak, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: nextStreak, reason: "continued"))
            outcome = .continued(previousStreak: previousStreak, currentStreak: nextStreak)
        } else {
            if previousStreak > 0 {
                AnalyticsService.shared.log(.returnStreakBroken(previousStreak: previousStreak))
            }
            defaults.set(1, forKey: streakKey)
            defaults.set(today, forKey: lastDayKey)
            AnalyticsService.shared.log(.returnStreakQualified(currentStreak: 1, reason: "restarted_after_gap"))
            outcome = previousStreak > 0 ? .brokenThenStarted(previousStreak: previousStreak) : .started(currentStreak: 1)
        }

        lastRecordOutcome = outcome
        objectWillChange.send()
        Task {
            await ReturnStreakReminderService.shared.refreshScheduleIfNeeded(userId: userId)
        }
        return outcome
    }

    func hasQualifiedToday(userId: String? = nil) -> Bool {
        guard let userId = resolvedUserId(userId),
              let lastDay = defaults.object(forKey: lastDayKey(userId: userId)) as? Date else {
            return false
        }
        return calendar.isDate(lastDay, inSameDayAs: calendar.startOfDay(for: now()))
    }

    // MARK: - Private

    private func resolvedUserId(_ userId: String?) -> String? {
        if let userId, !userId.isEmpty { return userId }
        return activeUserId
    }

    private func streakKey(userId: String) -> String {
        "returnStreak.\(userId).currentStreak"
    }

    private func lastDayKey(userId: String) -> String {
        "returnStreak.\(userId).lastQualifyingDay"
    }

    private func migrateLegacyDeviceStateIfNeeded(for userId: String) {
        let userStreakKey = streakKey(userId: userId)
        let userLastDayKey = lastDayKey(userId: userId)

        if defaults.object(forKey: userLastDayKey) != nil { return }

        let legacyStreak = defaults.integer(forKey: LegacyDefaultsKey.currentStreak)
        guard legacyStreak > 0,
              let legacyLastDay = defaults.object(forKey: LegacyDefaultsKey.lastReturnDay) as? Date else {
            return
        }

        defaults.set(legacyStreak, forKey: userStreakKey)
        defaults.set(legacyLastDay, forKey: userLastDayKey)
        defaults.removeObject(forKey: LegacyDefaultsKey.currentStreak)
        defaults.removeObject(forKey: LegacyDefaultsKey.lastReturnDay)
    }
}
