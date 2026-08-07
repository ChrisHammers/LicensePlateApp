//
//  NotificationRoutingServiceTests.swift
//  LicensePlateAppTests
//
//  Auth-switch rebind: ensureObserving tracks the current user and clears on stop / nil.
//

import Foundation
import UserNotifications
import Testing
@testable import LicensePlateApp

/// Fixed permission status so eligibility work stays out of rebind assertions.
private final class StubNotificationPermissionProvider: NotificationPermissionProviding {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        .denied
    }
}

@MainActor
struct NotificationRoutingServiceTests {

    private func makeService() -> NotificationRoutingService {
        let eligibility = NotificationEligibilityService(
            permissionProvider: StubNotificationPermissionProvider()
        )
        return NotificationRoutingService(
            eligibilityService: eligibility,
            analytics: AnalyticsLoggingSpy()
        )
    }

    @Test func ensureObservingBindsUserId() {
        let service = makeService()
        defer { service.stopObserving() }

        service.ensureObserving(userId: "user-a")
        #expect(service.observingUserId == "user-a")
    }

    @Test func ensureObservingRebindsWhenUserChanges() {
        let service = makeService()
        defer { service.stopObserving() }

        service.ensureObserving(userId: "user-a")
        service.ensureObserving(userId: "user-b")
        #expect(service.observingUserId == "user-b")
    }

    @Test func ensureObservingSameUserIsIdempotent() {
        let service = makeService()
        defer { service.stopObserving() }

        service.ensureObserving(userId: "user-a")
        service.ensureObserving(userId: "user-a")
        #expect(service.observingUserId == "user-a")
    }

    @Test func ensureObservingNilStopsObserving() {
        let service = makeService()

        service.ensureObserving(userId: "user-a")
        service.ensureObserving(userId: nil)
        #expect(service.observingUserId == nil)
    }

    @Test func ensureObservingEmptyStopsObserving() {
        let service = makeService()

        service.ensureObserving(userId: "user-a")
        service.ensureObserving(userId: "")
        #expect(service.observingUserId == nil)
    }

    @Test func stopObservingClearsUserId() {
        let service = makeService()

        service.ensureObserving(userId: "user-a")
        service.stopObserving()
        #expect(service.observingUserId == nil)
    }
}
