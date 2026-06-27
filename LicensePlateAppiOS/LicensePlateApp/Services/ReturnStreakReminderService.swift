//
//  ReturnStreakReminderService.swift
//  LicensePlateApp
//
//  Optional end-of-day local reminder when the user has not yet qualified their streak today.
//

import Foundation
import UserNotifications

@MainActor
final class ReturnStreakReminderService {
    static let shared = ReturnStreakReminderService(
        remoteConfig: RemoteConfigService.shared,
        streakService: ReturnStreakService.shared,
        eligibilityService: NotificationEligibilityService(permissionProvider: SystemNotificationPermissionProvider()),
        scheduler: UNUserNotificationCenter.current()
    )

    private static let reminderIdentifier = "return-streak-daily"
    private static let userDefaultsEnabledKey = "returnStreakRemindersEnabled"

    private let remoteConfig: RemoteConfigValueProviding
    private let streakService: ReturnStreakService
    private let eligibilityService: NotificationEligibilityService
    private let scheduler: LocalNotificationScheduling
    private let defaults: UserDefaults

    init(
        remoteConfig: RemoteConfigValueProviding,
        streakService: ReturnStreakService,
        eligibilityService: NotificationEligibilityService,
        scheduler: LocalNotificationScheduling,
        defaults: UserDefaults = .standard
    ) {
        self.remoteConfig = remoteConfig
        self.streakService = streakService
        self.eligibilityService = eligibilityService
        self.scheduler = scheduler
        self.defaults = defaults
    }

    var isUserEnabled: Bool {
        defaults.object(forKey: Self.userDefaultsEnabledKey) as? Bool ?? true
    }

    func setUserEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.userDefaultsEnabledKey)
        if !enabled {
            cancelReminder(reason: "user_disabled")
        }
    }

    func refreshScheduleIfNeeded(userId: String?) async {
        guard let userId, !userId.isEmpty else {
            cancelReminder(reason: "no_user")
            return
        }

        guard remoteConfig.bool(for: .returnStreakReminderEnabled), isUserEnabled else {
            cancelReminder(reason: "remote_config_or_user_disabled")
            return
        }

        guard streakService.isEnabled else {
            cancelReminder(reason: "streak_disabled")
            return
        }

        let state = streakService.currentState(for: userId)
        guard state.currentStreak >= streakService.minDisplayStreak else {
            cancelReminder(reason: "below_display_threshold")
            return
        }

        if streakService.hasQualifiedToday(userId: userId) {
            cancelReminder(reason: "already_qualified_today")
            return
        }

        let eligibility = await eligibilityService.eligibility(for: .returnStreakReminder)
        AnalyticsService.shared.log(
            .notificationEligibilityChecked(kind: eligibility.kind.rawValue, eligible: eligibility.isEligible)
        )
        guard eligibility.isEligible else {
            cancelReminder(reason: eligibility.denialReason ?? "not_eligible")
            return
        }

        let hour = remoteConfig.int(for: .returnStreakReminderHour)
        let content = UNMutableNotificationContent()
        content.title = "return_streak.reminder.title".localized
        content.body = "return_streak.reminder.body".localized
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = min(23, max(0, hour))
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.reminderIdentifier,
            content: content,
            trigger: trigger
        )

        scheduler.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        do {
            try await scheduler.add(request)
            AnalyticsService.shared.log(.returnStreakReminderScheduled(hour: hour))
        } catch {
            AnalyticsService.shared.log(.notificationDeliveryFailed(error: error.localizedDescription))
            CrashReportingService.shared.record(error: error, context: "schedule_return_streak_reminder")
        }
    }

    func cancelReminder(reason: String) {
        scheduler.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        AnalyticsService.shared.log(.reminderCancelled(sessionId: "return_streak", reason: reason))
    }

    /// Call when app becomes active; logs reminder conversion if user opened from streak reminder.
    func logReminderOpenedIfNeeded(userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        guard defaults.bool(forKey: "returnStreakReminderPendingOpen") else { return }
        defaults.set(false, forKey: "returnStreakReminderPendingOpen")
        let streak = streakService.currentState(for: userId).currentStreak
        AnalyticsService.shared.log(.returnStreakReminderOpened(currentStreak: streak))
    }

    static func markReminderPendingOpen() {
        UserDefaults.standard.set(true, forKey: "returnStreakReminderPendingOpen")
    }
}
