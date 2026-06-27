import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct ReturnStreakViewModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeStreakService(
        defaults: UserDefaults,
        now: @escaping () -> Date,
        enabled: Bool = true
    ) -> ReturnStreakService {
        ReturnStreakService(
            remoteConfig: MockRemoteConfigValues(
                bools: [
                    .returnStreakEnabled: enabled,
                    .returnStreakCelebrationEnabled: true,
                ],
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

    @Test func hiddenWhenStreakBelowDisplayThreshold() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeStreakService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        let viewModel = ReturnStreakViewModel(streakService: service, rewardPresenter: RewardPresenter())

        service.setActiveUserId("user-a")
        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        viewModel.bind(userId: "user-a")

        #expect(!viewModel.presentation.isVisible)
        #expect(viewModel.presentation.currentStreak == 1)
    }

    @Test func visibleWhenStreakMeetsDisplayThreshold() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = makeStreakService(defaults: defaults, now: { currentDate })
        let viewModel = ReturnStreakViewModel(streakService: service, rewardPresenter: RewardPresenter())

        service.setActiveUserId("user-a")
        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        currentDate = Date(timeIntervalSince1970: 172_800)
        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        viewModel.bind(userId: "user-a")

        #expect(viewModel.presentation.isVisible)
        #expect(viewModel.presentation.currentStreak == 2)
    }

    @Test func hiddenWhenRemoteConfigDisabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = makeStreakService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) },
            enabled: false
        )
        let viewModel = ReturnStreakViewModel(streakService: service, rewardPresenter: RewardPresenter())

        defaults.set(5, forKey: "returnStreak.user-a.currentStreak")
        defaults.set(Date(timeIntervalSince1970: 86_400), forKey: "returnStreak.user-a.lastQualifyingDay")
        viewModel.bind(userId: "user-a")

        #expect(!viewModel.presentation.isVisible)
    }

    @Test func celebrationQueuedWhenStreakContinuesPastThreshold() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var currentDate = Date(timeIntervalSince1970: 86_400)
        let service = makeStreakService(defaults: defaults, now: { currentDate })
        let presenter = RewardPresenter()
        let viewModel = ReturnStreakViewModel(streakService: service, rewardPresenter: presenter)

        service.setActiveUserId("user-a")
        viewModel.bind(userId: "user-a")

        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")
        viewModel.refresh()
        #expect(presenter.current == nil)

        currentDate = Date(timeIntervalSince1970: 172_800)
        _ = service.recordQualifyingFindIfNeeded(userId: "user-a")

        #expect(presenter.current != nil)
        if case .returnStreak(let days) = presenter.current {
            #expect(days == 2)
        } else {
            Issue.record("Expected return streak celebration")
        }
    }
}
