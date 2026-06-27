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

    private func makeService(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        enabled: Bool = true
    ) -> ReturnStreakService {
        ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(
                bools: [.returnStreakEnabled: enabled],
                ints: [
                    .returnStreakMinDisplay: 2,
                    .returnStreakCelebrationMinStreak: 2,
                ]
            ),
            defaults: defaults,
            calendar: calendar,
            now: now
        )
    }

    private func regionFoundEvent(participantId: String) -> TripActivityEvent {
        TripActivityEvent(
            sessionId: UUID(),
            kind: .regionFound,
            actorId: participantId,
            payload: [
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.gameInstanceId: UUID().uuidString,
            ]
        )
    }

    @Test func sameDaySecondFindIsNoOp() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        service.setActiveUserId("user-a")

        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")

        #expect(service.currentState(for: "user-a").currentStreak == 1)
    }

    @Test func consecutiveDaysIncrement() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = makeService(defaults: defaults, now: { currentDate })
        service.setActiveUserId("user-a")

        let first = service.recordQualifyingFindIfNeeded(userId: "user-a")
        #expect(first == .started(currentStreak: 1))

        currentDate = Date(timeIntervalSince1970: 172_800)
        let second = service.recordQualifyingFindIfNeeded(userId: "user-a")
        #expect(second == .continued(previousStreak: 1, currentStreak: 2))
        #expect(service.currentState(for: "user-a").currentStreak == 2)
    }

    @Test func missedDayResetsToOne() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = makeService(defaults: defaults, now: { currentDate })
        service.setActiveUserId("user-a")

        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        currentDate = Date(timeIntervalSince1970: 259_200)
        let outcome = service.recordQualifyingFindIfNeeded(userId: "user-a")

        #expect(outcome == .brokenThenStarted(previousStreak: 1))
        #expect(service.currentState(for: "user-a").currentStreak == 1)
    }

    @Test func remoteConfigDisabledDoesNotMutate() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) },
            enabled: false
        )
        service.setActiveUserId("user-a")

        let outcome = service.recordQualifyingFindIfNeeded(userId: "user-a")
        #expect(outcome == .disabled)
        #expect(service.currentState(for: "user-a").currentStreak == 0)
    }

    @Test func usersAreIsolated() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )

        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        _ = service.recordQualifyingFindIfNeeded(userId: "user-b")

        #expect(service.currentState(for: "user-a").currentStreak == 1)
        #expect(service.currentState(for: "user-b").currentStreak == 1)
    }

    @Test func legacyDeviceStateMigratesToActiveUser() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(4, forKey: "returnStreak.currentStreak")
        defaults.set(Date(timeIntervalSince1970: 86_400), forKey: "returnStreak.lastReturnDay")

        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        service.setActiveUserId("user-a")

        #expect(service.currentState(for: "user-a").currentStreak == 4)
        #expect(defaults.object(forKey: "returnStreak.currentStreak") == nil)
    }

    @Test func wrongParticipantDoesNotCount() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        service.setActiveUserId("user-a")

        let outcome = service.handleCommittedActivityEvent(regionFoundEvent(participantId: "other-user"))
        #expect(outcome == .noOp(alreadyQualifiedToday: false))
        #expect(service.currentState(for: "user-a").currentStreak == 0)
    }

    @Test func matchingParticipantCountsViaObserverPath() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        service.setActiveUserId("user-a")

        let outcome = service.handleCommittedActivityEvent(regionFoundEvent(participantId: "user-a"))
        #expect(outcome == .started(currentStreak: 1))
    }

    @Test func hasQualifiedTodayReflectsCalendarDay() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = makeService(defaults: defaults, now: { currentDate })
        service.setActiveUserId("user-a")

        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        #expect(service.hasQualifiedToday(userId: "user-a"))

        currentDate = Date(timeIntervalSince1970: 172_800)
        #expect(!service.hasQualifiedToday(userId: "user-a"))
    }
}
