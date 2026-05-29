//
//  ReminderNotificationService.swift
//  LicensePlateApp
//
//  Step 18 — Local reminders for inactive active trips.
//

import Foundation
import UserNotifications

protocol LocalNotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: LocalNotificationScheduling {}

@MainActor
final class ReminderNotificationService {
    static let shared = ReminderNotificationService(
        remoteConfig: RemoteConfigService.shared,
        eligibilityService: NotificationEligibilityService(permissionProvider: SystemNotificationPermissionProvider()),
        scheduler: UNUserNotificationCenter.current()
    )

    private let remoteConfig: RemoteConfigValueProviding
    private let eligibilityService: NotificationEligibilityService
    private let scheduler: LocalNotificationScheduling

    init(
        remoteConfig: RemoteConfigValueProviding,
        eligibilityService: NotificationEligibilityService,
        scheduler: LocalNotificationScheduling
    ) {
        self.remoteConfig = remoteConfig
        self.eligibilityService = eligibilityService
        self.scheduler = scheduler
    }

    func scheduleInactiveActiveTripReminder(sessionId: UUID, tripName: String) async {
        guard remoteConfig.bool(for: .remindersEnabled) else {
            AnalyticsService.shared.log(.reminderCancelled(sessionId: sessionId.uuidString, reason: "remote_config_disabled"))
            cancelReminder(sessionId: sessionId, reason: "remote_config_disabled")
            return
        }

        let eligibility = await eligibilityService.eligibility(for: .inactiveActiveTripReminder)
        AnalyticsService.shared.log(.notificationEligibilityChecked(kind: eligibility.kind.rawValue, eligible: eligibility.isEligible))
        guard eligibility.isEligible else {
            AnalyticsService.shared.log(.reminderCancelled(sessionId: sessionId.uuidString, reason: eligibility.denialReason ?? "not_eligible"))
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Ready to keep playing?".localized
        content.body = "Your trip %@ is waiting for more plate finds.".localized(tripName)
        content.sound = .default

        let hours = max(1, remoteConfig.int(for: .inactiveActiveTripReminderHours))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3_600), repeats: false)
        let request = UNNotificationRequest(
            identifier: reminderIdentifier(sessionId: sessionId),
            content: content,
            trigger: trigger
        )

        do {
            try await scheduler.add(request)
            AnalyticsService.shared.log(.reminderScheduled(sessionId: sessionId.uuidString, hours: hours))
        } catch {
            AnalyticsService.shared.log(.notificationDeliveryFailed(error: error.localizedDescription))
            CrashReportingService.shared.record(error: error, context: "schedule_inactive_trip_reminder")
        }
    }

    func cancelReminder(sessionId: UUID, reason: String) {
        scheduler.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(sessionId: sessionId)])
        AnalyticsService.shared.log(.reminderCancelled(sessionId: sessionId.uuidString, reason: reason))
    }

    private func reminderIdentifier(sessionId: UUID) -> String {
        "inactive-trip-\(sessionId.uuidString)"
    }
}
