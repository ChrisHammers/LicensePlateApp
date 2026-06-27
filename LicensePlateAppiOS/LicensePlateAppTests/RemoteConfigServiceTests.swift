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
        #expect(defaults.string(for: .progressionCatalogPresentationV1).isEmpty)
    }
}
