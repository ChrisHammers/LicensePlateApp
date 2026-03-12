//
//  NotificationRoutingService.swift
//  LicensePlateApp
//
//  Step 08 — Routes notification events (e.g. trip invite received) to local notifications when eligible.
//

import Foundation
import UserNotifications
import Combine

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
    private var inviteCancellable: AnyCancellable?
    private var lastKnownIncomingCount: Int?
    private var hasSeededIncomingCount = false

    init(eligibilityService: NotificationEligibilityService, analytics: AnalyticsService) {
        self.eligibilityService = eligibilityService
        self.analytics = analytics
    }

    /// Call when main app is active (e.g. ContentView.onAppear) to start observing trip invite events.
    /// Listener is set up only once; pass current userId so we only notify when that user receives new incoming invites.
    func startObservingIfNeeded(userId: String?) {
        guard let userId = userId else { return }
        guard inviteCancellable == nil else { return }

        let repo = TripInviteRepository.shared
        inviteCancellable = repo.$tripInvites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                Task { @MainActor in
                    self?.handleTripInvitesUpdate(invites: invites, userId: userId)
                }
            }
    }

    func stopObserving() {
        inviteCancellable?.cancel()
        inviteCancellable = nil
        lastKnownIncomingCount = nil
        hasSeededIncomingCount = false
    }

    private func handleTripInvitesUpdate(invites: [TripInvite], userId: String) {
        let incomingCount = invites.filter { $0.toUserId == userId && $0.statusEnum == .pending }.count

        if !hasSeededIncomingCount {
            lastKnownIncomingCount = incomingCount
            hasSeededIncomingCount = true
            return
        }

        let previous = lastKnownIncomingCount ?? 0
        lastKnownIncomingCount = incomingCount

        if incomingCount > previous {
            Task.detached(priority: .utility) { [weak self] in
                await self?.handleTripInviteReceived()
            }
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
