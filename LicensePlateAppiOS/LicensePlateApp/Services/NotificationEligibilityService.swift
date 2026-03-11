//
//  NotificationEligibilityService.swift
//  LicensePlateApp
//
//  Step 08 — Permission-aware eligibility for notifications. Injectable permission provider for tests.
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

    init(permissionProvider: NotificationPermissionProviding) {
        self.permissionProvider = permissionProvider
    }

    /// Returns whether we can show a notification of the given kind (e.g. permission granted).
    func eligibility(for kind: NotificationEligibilityKind) async -> NotificationEligibility {
        let status = await permissionProvider.currentAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return NotificationEligibility(kind: kind, isEligible: true, denialReason: nil)
        case .denied:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "denied")
        case .notDetermined:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "notDetermined")
        @unknown default:
            return NotificationEligibility(kind: kind, isEligible: false, denialReason: "unknown")
        }
    }
}
