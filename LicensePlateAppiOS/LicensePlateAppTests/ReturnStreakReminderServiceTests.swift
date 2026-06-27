import Foundation
import Testing
import UserNotifications
@testable import LicensePlateApp

private final class MockStreakReminderScheduler: LocalNotificationScheduling {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

@MainActor
struct ReturnStreakReminderServiceTests {
    @Test func disabledRemoteConfigCancelsReminder() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let scheduler = MockStreakReminderScheduler()
        let streakService = ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.returnStreakEnabled: true, .returnStreakReminderEnabled: false],
                ints: [.returnStreakMinDisplay: 2]
            ),
            defaults: defaults,
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        defaults.set(3, forKey: "returnStreak.user-a.currentStreak")
        defaults.set(Date(timeIntervalSince1970: 86_400), forKey: "returnStreak.user-a.lastQualifyingDay")

        let service = ReturnStreakReminderService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.returnStreakEnabled: true, .returnStreakReminderEnabled: false],
                ints: [.returnStreakMinDisplay: 2, .returnStreakReminderHour: 20]
            ),
            streakService: streakService,
            eligibilityService: NotificationEligibilityService(
                permissionProvider: StreakReminderMockPermissionProvider(status: .authorized)
            ),
            scheduler: scheduler,
            defaults: defaults
        )

        await service.refreshScheduleIfNeeded(userId: "user-a")
        #expect(scheduler.addedRequests.isEmpty)
        #expect(scheduler.removedIdentifiers.contains("return-streak-daily"))
    }
}

@MainActor
private final class StreakReminderMockPermissionProvider: NotificationPermissionProviding {
    let status: UNAuthorizationStatus
    init(status: UNAuthorizationStatus) { self.status = status }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus { status }
}
