//
//  NotificationRoutingService.swift
//  LicensePlateApp
//
//  Step 08 — Routes notification events (trip / friend / family invite received)
//  to local notifications when eligible.
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
    private let analytics: AnalyticsLogging
    private var cancellables = Set<AnyCancellable>()

    /// User id currently captured by invite sinks; nil when not observing.
    private(set) var observingUserId: String?

    private var lastKnownIncomingTripCount: Int?
    private var hasSeededIncomingTripCount = false

    private var lastKnownIncomingFriendCount: Int?
    private var hasSeededIncomingFriendCount = false

    private var lastKnownIncomingFamilyCount: Int?
    private var hasSeededIncomingFamilyCount = false

    init(eligibilityService: NotificationEligibilityService, analytics: AnalyticsLogging) {
        self.eligibilityService = eligibilityService
        self.analytics = analytics
    }

    /// Bind invite publishers to `userId`. Rebinds when the user changes; no-ops if already observing that user.
    func ensureObserving(userId: String?) {
        guard let userId, !userId.isEmpty else {
            stopObserving()
            return
        }
        if observingUserId == userId, !cancellables.isEmpty {
            return
        }

        stopObserving()
        observingUserId = userId

        TripInviteRepository.shared.$tripInvites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                self?.handleTripInvitesUpdate(invites: invites, userId: userId)
            }
            .store(in: &cancellables)

        InviteRepository.shared.$invites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                self?.handleSocialInvitesUpdate(invites: invites, userId: userId)
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        cancellables.removeAll()
        observingUserId = nil
        lastKnownIncomingTripCount = nil
        hasSeededIncomingTripCount = false
        lastKnownIncomingFriendCount = nil
        hasSeededIncomingFriendCount = false
        lastKnownIncomingFamilyCount = nil
        hasSeededIncomingFamilyCount = false
    }

    private func handleTripInvitesUpdate(invites: [TripInvite], userId: String) {
        let incomingCount = invites.filter { $0.toUserId == userId && $0.statusEnum == .pending }.count

        if !hasSeededIncomingTripCount {
            lastKnownIncomingTripCount = incomingCount
            hasSeededIncomingTripCount = true
            return
        }

        let previous = lastKnownIncomingTripCount ?? 0
        lastKnownIncomingTripCount = incomingCount

        if incomingCount > previous {
            Task.detached(priority: .utility) { [weak self] in
                await self?.deliverLocalInviteNotification(
                    kind: .tripInvite,
                    titleKey: "New trip invite",
                    bodyKey: "You have a new trip invite. Open the app to view.",
                    requestPrefix: "trip-invite",
                    deliveredEvent: .notificationDeliveredTripInvite
                )
            }
        }
    }

    private func handleSocialInvitesUpdate(invites: [Invite], userId: String) {
        let counts = SocialInboxBadgeCounts.counts(from: invites, userId: userId)
        let friendCount = counts.friend
        let familyCount = counts.family

        if !hasSeededIncomingFriendCount {
            lastKnownIncomingFriendCount = friendCount
            hasSeededIncomingFriendCount = true
        } else {
            let previousFriend = lastKnownIncomingFriendCount ?? 0
            lastKnownIncomingFriendCount = friendCount
            if friendCount > previousFriend {
                Task.detached(priority: .utility) { [weak self] in
                    await self?.deliverLocalInviteNotification(
                        kind: .friendInvite,
                        titleKey: "New friend request",
                        bodyKey: "You have a new friend request. Open the app to view.",
                        requestPrefix: "friend-invite",
                        deliveredEvent: .notificationDeliveredFriendInvite
                    )
                }
            }
        }

        if !hasSeededIncomingFamilyCount {
            lastKnownIncomingFamilyCount = familyCount
            hasSeededIncomingFamilyCount = true
        } else {
            let previousFamily = lastKnownIncomingFamilyCount ?? 0
            lastKnownIncomingFamilyCount = familyCount
            if familyCount > previousFamily {
                Task.detached(priority: .utility) { [weak self] in
                    await self?.deliverLocalInviteNotification(
                        kind: .familyInvite,
                        titleKey: "New family invitation",
                        bodyKey: "You have a new family invitation. Open the app to view.",
                        requestPrefix: "family-invite",
                        deliveredEvent: .notificationDeliveredFamilyInvite
                    )
                }
            }
        }
    }

    private func deliverLocalInviteNotification(
        kind: NotificationEligibilityKind,
        titleKey: String,
        bodyKey: String,
        requestPrefix: String,
        deliveredEvent: AnalyticsService.Event
    ) async {
        let eligibility = await eligibilityService.eligibility(for: kind)
        analytics.log(
            .notificationEligibilityChecked(
                kind: eligibility.kind.rawValue,
                eligible: eligibility.isEligible
            )
        )
        guard eligibility.isEligible else { return }

        let content = UNMutableNotificationContent()
        content.title = titleKey.localized
        content.body = bodyKey.localized
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(requestPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            analytics.log(deliveredEvent)
        } catch {
            analytics.log(.notificationDeliveryFailed(error: String(describing: error)))
        }
    }
}
