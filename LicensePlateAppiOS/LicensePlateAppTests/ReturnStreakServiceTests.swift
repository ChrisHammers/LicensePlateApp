import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct ReturnStreakServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func sameDayIsNoOp() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(bools: [.returnStreakEnabled: true]),
            defaults: defaults,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 86_400) }
        )

        _ = service.recordAppReturnIfNeeded()
        _ = service.recordAppReturnIfNeeded()

        #expect(service.currentState.currentStreak == 1)
    }

    @Test func nextDayIncrements() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(bools: [.returnStreakEnabled: true]),
            defaults: defaults,
            calendar: calendar,
            now: { currentDate }
        )

        _ = service.recordAppReturnIfNeeded()
        currentDate = Date(timeIntervalSince1970: 172_800)
        _ = service.recordAppReturnIfNeeded()

        #expect(service.currentState.currentStreak == 2)
    }

    @Test func missedDayResets() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(bools: [.returnStreakEnabled: true]),
            defaults: defaults,
            calendar: calendar,
            now: { currentDate }
        )

        _ = service.recordAppReturnIfNeeded()
        currentDate = Date(timeIntervalSince1970: 259_200)
        _ = service.recordAppReturnIfNeeded()

        #expect(service.currentState.currentStreak == 1)
    }

    @Test func remoteConfigDisabledDoesNotMutate() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(bools: [.returnStreakEnabled: false]),
            defaults: defaults,
            calendar: calendar
        )

        _ = service.recordAppReturnIfNeeded()

        #expect(service.currentState.currentStreak == 0)
    }
}
