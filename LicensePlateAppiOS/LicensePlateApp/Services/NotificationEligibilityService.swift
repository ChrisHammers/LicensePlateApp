//
//  NotificationEligibilityService.swift
//  LicensePlateApp
//
//  Step 08 — Permission ∧ prefs eligibility for notifications. Injectable for tests.
//

import Foundation
import UserNotifications

/// Provides current notification authorization status (injectable for tests).
protocol NotificationPermissionProviding: AnyObject {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
}

/// Production provider using system notification center.
@MainActor
final class SystemNotificationPermissionProvider: NotificationPermissionProviding {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}

@MainActor
final class NotificationEligibilityService {
    private let permissionProvider: NotificationPermissionProviding
    private let prefsReader: NotificationPrefsReading

    init(
        permissionProvider: NotificationPermissionProviding,
        prefsReader: NotificationPrefsReading = NotificationPrefsStore.shared
    ) {
        self.permissionProvider = permissionProvider
        self.prefsReader = prefsReader
    }

    /// Returns whether we can show a notification of the given kind (permission ∧ account pref).
    func eligibility(for kind: NotificationEligibilityKind) async -> NotificationEligibility {
        let status = await permissionProvider.currentAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "denied")
        case .notDetermined:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "notDetermined")
        @unknown default:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "unknown")
        }

        guard prefsReader.prefs.isEnabled(for: kind) else {
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "pref_disabled")
        }
        return NotificationEligibility(kind: kind, isEligible: true, denialReason: nil)
    }
}
