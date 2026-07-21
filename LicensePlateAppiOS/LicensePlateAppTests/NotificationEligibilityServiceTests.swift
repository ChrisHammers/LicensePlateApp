//
//  NotificationEligibilityServiceTests.swift
//  LicensePlateAppTests
//
//  Step 08 — NotificationEligibilityService: eligibility by permission ∧ prefs.
//

import Foundation
import UserNotifications
import Testing
@testable import LicensePlateApp

/// Mock provider that returns a fixed authorization status.
private final class MockNotificationPermissionProvider: NotificationPermissionProviding {
    let status: UNAuthorizationStatus

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        status
    }
}

@MainActor
private final class MockNotificationPrefsReader: NotificationPrefsReading {
    var prefs: UserRepository.NotificationPrefs

    init(prefs: UserRepository.NotificationPrefs = .default) {
        self.prefs = prefs
    }
}

@MainActor
struct NotificationEligibilityServiceTests {

    @Test func eligibilityWhenAuthorizedReturnsEligible() async {
        let provider = MockNotificationPermissionProvider(status: .authorized)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .tripInvite)
        #expect(result.kind == .tripInvite)
        #expect(result.isEligible == true)
        #expect(result.denialReason == nil)
    }

    @Test func eligibilityWhenProvisionalReturnsEligible() async {
        let provider = MockNotificationPermissionProvider(status: .provisional)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .tripInvite)
        #expect(result.isEligible == true)
        #expect(result.denialReason == nil)
    }

    @Test func eligibilityWhenDeniedReturnsNotEligible() async {
        let provider = MockNotificationPermissionProvider(status: .denied)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .tripInvite)
        #expect(result.kind == .tripInvite)
        #expect(result.isEligible == false)
        #expect(result.denialReason == "denied")
    }

    @Test func eligibilityWhenNotDeterminedReturnsNotEligible() async {
        let provider = MockNotificationPermissionProvider(status: .notDetermined)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .tripInvite)
        #expect(result.isEligible == false)
        #expect(result.denialReason == "notDetermined")
    }

    @Test func eligibilityRespectsDisabledPref() async {
        var prefs = UserRepository.NotificationPrefs.default
        prefs.tripInvite = false
        let provider = MockNotificationPermissionProvider(status: .authorized)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader(prefs: prefs)
        )
        let result = await service.eligibility(for: .tripInvite)
        #expect(result.isEligible == false)
        #expect(result.denialReason == "pref_disabled")
    }

    @Test func eligibilityForMilestoneKindUsesSamePermission() async {
        let provider = MockNotificationPermissionProvider(status: .authorized)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .milestone)
        #expect(result.kind == .milestone)
        #expect(result.isEligible == true)
    }

    @Test func eligibilityForInactiveTripReminderUsesSamePermission() async {
        let provider = MockNotificationPermissionProvider(status: .authorized)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .inactiveActiveTripReminder)
        #expect(result.kind == .inactiveActiveTripReminder)
        #expect(result.isEligible == true)
    }

    @Test func eligibilityForFriendInviteUsesSamePermission() async {
        let provider = MockNotificationPermissionProvider(status: .authorized)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .friendInvite)
        #expect(result.kind == .friendInvite)
        #expect(result.isEligible == true)
    }

    @Test func eligibilityForFamilyInviteUsesSamePermission() async {
        let provider = MockNotificationPermissionProvider(status: .denied)
        let service = NotificationEligibilityService(
            permissionProvider: provider,
            prefsReader: MockNotificationPrefsReader()
        )
        let result = await service.eligibility(for: .familyInvite)
        #expect(result.kind == .familyInvite)
        #expect(result.isEligible == false)
        #expect(result.denialReason == "denied")
    }
}
