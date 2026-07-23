import Testing
@testable import LicensePlateApp

struct RemoteConfigServiceTests {
    @Test func defaultsProvideLaunchGrowthValues() {
        let defaults = RemoteConfigDefaultsProvider()

        #expect(defaults.bool(for: .adsEnabledFreeTier))
        #expect(defaults.bool(for: .reviewPromptEnabled))
        #expect(defaults.int(for: .reviewPromptMinimumCompletedTrips) == 1)
        #expect(defaults.int(for: .reviewPromptCooldownDays) == 120)
        #expect(defaults.bool(for: .remindersEnabled))
        #expect(defaults.int(for: .inactiveActiveTripReminderHours) == 24)
        #expect(defaults.bool(for: .returnStreakEnabled))
        #expect(defaults.int(for: .returnStreakMinDisplay) == 2)
        #expect(defaults.int(for: .returnStreakCelebrationMinStreak) == 2)
        #expect(!defaults.bool(for: .returnStreakReminderEnabled))
        #expect(defaults.int(for: .returnStreakReminderHour) == 20)
        #expect(defaults.string(for: .progressionCatalogPresentationV1).isEmpty)
        #expect(defaults.string(for: .appUpdatePolicyV1).isEmpty)
        #expect(!defaults.bool(for: .quickSoloFirstSessionEnabled))
        #expect(defaults.int(for: .quickSoloSplashDelayMs) == 1000)
    }
}
