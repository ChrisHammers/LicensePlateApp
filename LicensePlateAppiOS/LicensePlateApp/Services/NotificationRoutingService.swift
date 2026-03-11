//
//  NotificationRoutingService.swift
//  LicensePlateApp
//
//  Step 08 — Routes notification events (e.g. trip invite received) to local notifications when eligible.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationRoutingService {
    static let shared: NotificationRoutingService = {
        let provider = SystemNotificationPermissionProvider()
        let eligibility = NotificationEligibilityService(permissionProvider: provider)
        return NotificationRoutingService(
            eligibilityService: eligibility,
            analytics: AnalyticsService.shared
        )
    }()

    private let eligibilityService: NotificationEligibilityService
    private let analytics: AnalyticsService
    private var tripInviteObserver: Any?

    init(eligibilityService: NotificationEligibilityService, analytics: AnalyticsService) {
        self.eligibilityService = eligibilityService
        self.analytics = analytics
    }

    /// Call when main app is active (e.g. ContentView.onAppear) to start observing trip invite events.
    func startObservingIfNeeded() {
        guard tripInviteObserver == nil else { return }
        tripInviteObserver = NotificationCenter.default.addObserver(
            forName: .tripInviteReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleTripInviteReceived()
            }
        }
    }

    func stopObserving() {
        if let observer = tripInviteObserver {
            NotificationCenter.default.removeObserver(observer)
            tripInviteObserver = nil
        }
    }

    private func handleTripInviteReceived() async {
        let eligibility = await eligibilityService.eligibility(for: .tripInvite)
        analytics.log(
            .notificationEligibilityChecked(
                kind: eligibility.kind.rawValue,
                eligible: eligibility.isEligible
            )
        )
        guard eligibility.isEligible else { return }

        let content = UNMutableNotificationContent()
        content.title = "New trip invite".localized
        content.body = "You have a new trip invite. Open the app to view.".localized
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-invite-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            analytics.log(.notificationDeliveredTripInvite)
        } catch {
            // Log but don't surface; notification delivery is best-effort
            analytics.log("notification_delivery_failed", parameters: ["error": "\(error)"])
        }
    }
}
