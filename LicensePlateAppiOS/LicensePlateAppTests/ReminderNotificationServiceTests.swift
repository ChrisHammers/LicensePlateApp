import Foundation
import Testing
import UserNotifications
@testable import LicensePlateApp

private final class LocalNotificationSchedulerSpy: LocalNotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

private final class FixedNotificationPermissionProvider: NotificationPermissionProviding {
    let status: UNAuthorizationStatus

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        status
    }
}

@MainActor
struct ReminderNotificationServiceTests {
    @Test func schedulesWhenEnabledAndAuthorized() async {
        let scheduler = LocalNotificationSchedulerSpy()
        let service = ReminderNotificationService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.remindersEnabled: true],
                ints: [.inactiveActiveTripReminderHours: 12]
            ),
            eligibilityService: NotificationEligibilityService(
                permissionProvider: FixedNotificationPermissionProvider(status: .authorized)
            ),
            scheduler: scheduler
        )

        await service.scheduleInactiveActiveTripReminder(sessionId: UUID(), tripName: "Test Trip")

        #expect(scheduler.addedRequests.count == 1)
    }

    @Test func permissionSuppressionDoesNotSchedule() async {
        let scheduler = LocalNotificationSchedulerSpy()
        let service = ReminderNotificationService(
            remoteConfig: MockRemoteConfigValues(bools: [.remindersEnabled: true]),
            eligibilityService: NotificationEligibilityService(
                permissionProvider: FixedNotificationPermissionProvider(status: .denied)
            ),
            scheduler: scheduler
        )

        await service.scheduleInactiveActiveTripReminder(sessionId: UUID(), tripName: "Test Trip")

        #expect(scheduler.addedRequests.isEmpty)
    }

    @Test func remoteConfigDisabledCancelsPendingReminder() async {
        let scheduler = LocalNotificationSchedulerSpy()
        let sessionId = UUID()
        let service = ReminderNotificationService(
            remoteConfig: MockRemoteConfigValues(bools: [.remindersEnabled: false]),
            eligibilityService: NotificationEligibilityService(
                permissionProvider: FixedNotificationPermissionProvider(status: .authorized)
            ),
            scheduler: scheduler
        )

        await service.scheduleInactiveActiveTripReminder(sessionId: sessionId, tripName: "Test Trip")

        #expect(scheduler.addedRequests.isEmpty)
        #expect(scheduler.removedIdentifiers.contains("inactive-trip-\(sessionId.uuidString)"))
    }
}
