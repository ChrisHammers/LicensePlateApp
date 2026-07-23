//
//  RemoteConfigService.swift
//  LicensePlateApp
//
//  Step 18 — Typed Remote Config defaults for launch-growth features.
//

import Foundation
import Combine

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

protocol RemoteConfigValueProviding {
    func bool(for key: RemoteConfigService.Key) -> Bool
    func int(for key: RemoteConfigService.Key) -> Int
    func string(for key: RemoteConfigService.Key) -> String
}

struct RemoteConfigDefaultsProvider: RemoteConfigValueProviding {
    func bool(for key: RemoteConfigService.Key) -> Bool {
        switch key {
        case .adsEnabledFreeTier, .reviewPromptEnabled, .remindersEnabled, .returnStreakEnabled,
             .returnStreakCelebrationEnabled, .founderProgramEnabled:
            return true
        case .returnStreakReminderEnabled, .quickSoloFirstSessionEnabled:
            return false
        case .reviewPromptMinimumCompletedTrips, .reviewPromptCooldownDays, .inactiveActiveTripReminderHours,
             .returnStreakMinDisplay, .returnStreakCelebrationMinStreak, .returnStreakReminderHour,
             .quickSoloSplashDelayMs:
            return int(for: key) != 0
        case .progressionRewardsPresentationV1, .progressionCatalogPresentationV1, .progressionCatalogXpToastV1,
             .appUpdatePolicyV1:
            return !string(for: key).isEmpty
        }
    }

    func int(for key: RemoteConfigService.Key) -> Int {
        switch key {
        case .reviewPromptMinimumCompletedTrips:
            return 1
        case .reviewPromptCooldownDays:
            return 120
        case .inactiveActiveTripReminderHours:
            return 24
        case .returnStreakMinDisplay, .returnStreakCelebrationMinStreak:
            return 2
        case .returnStreakReminderHour:
            return 20
        case .quickSoloSplashDelayMs:
            return 1000
        case .adsEnabledFreeTier, .reviewPromptEnabled, .remindersEnabled, .returnStreakEnabled,
             .returnStreakCelebrationEnabled, .founderProgramEnabled, .quickSoloFirstSessionEnabled:
            return bool(for: key) ? 1 : 0
        case .returnStreakReminderEnabled:
            return 0
        case .progressionRewardsPresentationV1, .progressionCatalogPresentationV1, .progressionCatalogXpToastV1,
             .appUpdatePolicyV1:
            return string(for: key).isEmpty ? 0 : 1
        }
    }

    func string(for key: RemoteConfigService.Key) -> String {
        switch key {
        case .progressionRewardsPresentationV1, .progressionCatalogPresentationV1, .progressionCatalogXpToastV1,
             .appUpdatePolicyV1:
            return ""
        default:
            return ""
        }
    }
}

@MainActor
final class RemoteConfigService: ObservableObject, RemoteConfigValueProviding {
    enum Key: String, CaseIterable {
        case adsEnabledFreeTier = "ads_enabled_free_tier"
        case reviewPromptEnabled = "review_prompt_enabled"
        case reviewPromptMinimumCompletedTrips = "review_prompt_minimum_completed_trips"
        case reviewPromptCooldownDays = "review_prompt_cooldown_days"
        case remindersEnabled = "reminders_enabled"
        case inactiveActiveTripReminderHours = "inactive_active_trip_reminder_hours"
        case returnStreakEnabled = "return_streak_enabled"
        case returnStreakMinDisplay = "return_streak_min_display"
        case returnStreakCelebrationEnabled = "return_streak_celebration_enabled"
        case returnStreakCelebrationMinStreak = "return_streak_celebration_min_streak"
        case returnStreakReminderEnabled = "return_streak_reminder_enabled"
        case returnStreakReminderHour = "return_streak_reminder_hour"
        case founderProgramEnabled = "founder_program_enabled"
        case progressionRewardsPresentationV1 = "progression_rewards_presentation_v1"
        case progressionCatalogPresentationV1 = "progression_catalog_presentation_v1"
        case progressionCatalogXpToastV1 = "progression_catalog_xp_toast_v1"
        case quickSoloFirstSessionEnabled = "quick_solo_first_session_enabled"
        case quickSoloSplashDelayMs = "quick_solo_splash_delay_ms"
        case appUpdatePolicyV1 = "app_update_policy_v1"
    }

    static let shared = RemoteConfigService()

    private let defaults = RemoteConfigDefaultsProvider()

    #if canImport(FirebaseRemoteConfig)
    private lazy var remoteConfig: RemoteConfig = {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3_600
        #endif
        config.configSettings = settings
        config.setDefaults(defaultValues as NSDictionary as! [String : NSObject])
        return config
    }()
    #endif

    private init() {}

    func fetchAndActivate() async {
        #if canImport(FirebaseRemoteConfig)
        do {
            _ = try await remoteConfig.fetchAndActivate()
            AnalyticsService.shared.log(.remoteConfigFetchSucceeded)
        } catch {
            AnalyticsService.shared.log(.remoteConfigFetchFailed(error: error.localizedDescription))
            CrashReportingService.shared.record(error: error, context: "remote_config_fetch")
        }
        #else
        AnalyticsService.shared.log(.remoteConfigFetchSucceeded)
        #endif
        ProgressionRewardsConfigProvider.shared.refresh(
            presentationOverrideJSON: string(for: .progressionRewardsPresentationV1)
        )
        ProgressionCatalogProvider.shared.refresh(
            presentationOverrideJSON: string(for: .progressionCatalogPresentationV1),
            xpToastOverrideJSON: string(for: .progressionCatalogXpToastV1)
        )
    }

    func bool(for key: Key) -> Bool {
        #if canImport(FirebaseRemoteConfig)
        return remoteConfig.configValue(forKey: key.rawValue).boolValue
        #else
        return defaults.bool(for: key)
        #endif
    }

    func int(for key: Key) -> Int {
        #if canImport(FirebaseRemoteConfig)
        return remoteConfig.configValue(forKey: key.rawValue).numberValue.intValue
        #else
        return defaults.int(for: key)
        #endif
    }

    func string(for key: Key) -> String {
        #if canImport(FirebaseRemoteConfig)
        return remoteConfig.configValue(forKey: key.rawValue).stringValue
        #else
        return defaults.string(for: key)
        #endif
    }

    var adsEnabledFreeTier: Bool { bool(for: .adsEnabledFreeTier) }
    var reviewPromptEnabled: Bool { bool(for: .reviewPromptEnabled) }
    var reviewPromptMinimumCompletedTrips: Int { max(1, int(for: .reviewPromptMinimumCompletedTrips)) }
    var reviewPromptCooldownDays: Int { max(1, int(for: .reviewPromptCooldownDays)) }
    var remindersEnabled: Bool { bool(for: .remindersEnabled) }
    var inactiveActiveTripReminderHours: Int { max(1, int(for: .inactiveActiveTripReminderHours)) }
    var returnStreakEnabled: Bool { bool(for: .returnStreakEnabled) }
    var returnStreakMinDisplay: Int { max(1, int(for: .returnStreakMinDisplay)) }
    var returnStreakCelebrationEnabled: Bool { bool(for: .returnStreakCelebrationEnabled) }
    var returnStreakCelebrationMinStreak: Int { max(1, int(for: .returnStreakCelebrationMinStreak)) }
    var returnStreakReminderEnabled: Bool { bool(for: .returnStreakReminderEnabled) }
    var returnStreakReminderHour: Int { min(23, max(0, int(for: .returnStreakReminderHour))) }
    var founderProgramEnabled: Bool { bool(for: .founderProgramEnabled) }
    var quickSoloFirstSessionEnabled: Bool { bool(for: .quickSoloFirstSessionEnabled) }
    var quickSoloSplashDelayMs: Int { max(0, int(for: .quickSoloSplashDelayMs)) }
    var appUpdatePolicyJSON: String { string(for: .appUpdatePolicyV1) }

    private var defaultValues: [String: NSObject] {
        [
            Key.adsEnabledFreeTier.rawValue: defaults.bool(for: .adsEnabledFreeTier) as NSNumber,
            Key.reviewPromptEnabled.rawValue: defaults.bool(for: .reviewPromptEnabled) as NSNumber,
            Key.reviewPromptMinimumCompletedTrips.rawValue: defaults.int(for: .reviewPromptMinimumCompletedTrips) as NSNumber,
            Key.reviewPromptCooldownDays.rawValue: defaults.int(for: .reviewPromptCooldownDays) as NSNumber,
            Key.remindersEnabled.rawValue: defaults.bool(for: .remindersEnabled) as NSNumber,
            Key.inactiveActiveTripReminderHours.rawValue: defaults.int(for: .inactiveActiveTripReminderHours) as NSNumber,
            Key.returnStreakEnabled.rawValue: defaults.bool(for: .returnStreakEnabled) as NSNumber,
            Key.returnStreakMinDisplay.rawValue: defaults.int(for: .returnStreakMinDisplay) as NSNumber,
            Key.returnStreakCelebrationEnabled.rawValue: defaults.bool(for: .returnStreakCelebrationEnabled) as NSNumber,
            Key.returnStreakCelebrationMinStreak.rawValue: defaults.int(for: .returnStreakCelebrationMinStreak) as NSNumber,
            Key.returnStreakReminderEnabled.rawValue: defaults.bool(for: .returnStreakReminderEnabled) as NSNumber,
            Key.returnStreakReminderHour.rawValue: defaults.int(for: .returnStreakReminderHour) as NSNumber,
            Key.founderProgramEnabled.rawValue: defaults.bool(for: .founderProgramEnabled) as NSNumber,
            Key.progressionRewardsPresentationV1.rawValue: defaults.string(for: .progressionRewardsPresentationV1) as NSString,
            Key.progressionCatalogPresentationV1.rawValue: defaults.string(for: .progressionCatalogPresentationV1) as NSString,
            Key.progressionCatalogXpToastV1.rawValue: defaults.string(for: .progressionCatalogXpToastV1) as NSString,
            Key.quickSoloFirstSessionEnabled.rawValue: defaults.bool(for: .quickSoloFirstSessionEnabled) as NSNumber,
            Key.quickSoloSplashDelayMs.rawValue: defaults.int(for: .quickSoloSplashDelayMs) as NSNumber,
            Key.appUpdatePolicyV1.rawValue: defaults.string(for: .appUpdatePolicyV1) as NSString
        ]
    }
}
