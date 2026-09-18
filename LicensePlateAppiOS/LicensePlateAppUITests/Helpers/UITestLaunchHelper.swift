//
//  UITestLaunchHelper.swift
//  LicensePlateAppUITests
//
//  Step 13 — Launch app with optional arguments/environment for UI tests.
//

import XCTest

/// Use launch arguments or environment so the app (when built with test-only code path for --uitest) can skip onboarding, seed data, or force flow variants.
enum UITestLaunchHelper {
    static let launchArgUITest = "--uitest"
    static let launchArgSkipOnboarding = "--skipOnboarding"
    static let launchArgQuickSoloFirstSession = "--quickSoloFirstSession"
    static let launchArgLegacyOnboarding = "--legacyOnboarding"
    static let launchArgSeedTripWithTwoGames = "--seedTripWithTwoGames"
    static let launchArgSeedCollaborativeTrip = "--seedCollaborativeTrip"
    static let launchArgSeedTripWithRiskFlags = "--seedTripWithRiskFlags"

    /// `UserDefaults` argument-domain override for `AppCoordinator`'s `@AppStorage("hasSeenOnboarding")`.
    ///
    /// No launch flag skips the splash: `RootView` always runs the real startup chain and only then
    /// calls `AppCoordinator.transitionFromSplash`, which sends a user with `hasSeenOnboarding == true`
    /// straight to Home before it looks at `--legacyOnboarding` / `--quickSoloFirstSession`. A
    /// `--skipOnboarding` launch persists `hasSeenOnboarding = true` in the simulator's app container,
    /// so on every later run the first-session variants would land on Home instead. `-hasSeenOnboarding NO`
    /// puts a per-launch value in `NSArgumentDomain`, which `UserDefaults.standard` consults before the
    /// persisted app domain — the app's code and its stored data are untouched.
    static let launchArgsFreshOnboardingState = ["-hasSeenOnboarding", "NO"]

    /// How long a test may wait for the first post-splash screen.
    ///
    /// The splash stays up for the whole startup chain in `RootView` — Remote Config fetch,
    /// `initializeAuthState` (Keychain / Firestore restore), the rest of the wiring, then the
    /// `quick_solo_splash_delay_ms` minimum — and no launch argument shortens it. With a healthy
    /// network the chain finishes in a few seconds, but every step is a network request with a
    /// 60 s timeout, and on the development Mac those requests intermittently stall on an unsatisfied
    /// IPv6 route to Google until they time out (simulator log: `No network route` / `Network is
    /// down`, then an immediate retry that succeeds). One stall puts the first screen at ~60–75 s
    /// after launch; two in one launch were measured past 120 s. The original 8 s never had a
    /// chance. `waitForExistence` returns as soon as the element appears, so this ceiling only
    /// costs time on a genuine failure.
    static let startupTimeout: TimeInterval = 180

    static let envKeyTestUserId = "UITEST_USER_ID"
    static let envKeyAnalyticsDisabled = "UITEST_ANALYTICS_DISABLED"

    static func launchArguments(
        uitest: Bool = true,
        skipOnboarding: Bool = false,
        quickSoloFirstSession: Bool = false,
        legacyOnboarding: Bool = false,
        seedTripWithTwoGames: Bool = false,
        seedCollaborativeTrip: Bool = false,
        seedTripWithRiskFlags: Bool = false
    ) -> [String] {
        var args: [String] = []
        // The `-key value` pair goes first so NSUserDefaults' argument parser pairs it correctly no
        // matter how many bare `--flags` follow. Not combined with `--skipOnboarding`: that flag
        // exists to land on Home, and an argument-domain value wins over the app's own write.
        if (legacyOnboarding || quickSoloFirstSession) && !skipOnboarding {
            args.append(contentsOf: launchArgsFreshOnboardingState)
        }
        if uitest { args.append(launchArgUITest) }
        if skipOnboarding { args.append(launchArgSkipOnboarding) }
        if quickSoloFirstSession { args.append(launchArgQuickSoloFirstSession) }
        if legacyOnboarding { args.append(launchArgLegacyOnboarding) }
        if seedTripWithTwoGames { args.append(launchArgSeedTripWithTwoGames) }
        if seedCollaborativeTrip { args.append(launchArgSeedCollaborativeTrip) }
        if seedTripWithRiskFlags { args.append(launchArgSeedTripWithRiskFlags) }
        return args
    }

    static func launchEnvironment(
        testUserId: String? = nil,
        analyticsDisabled: Bool = true
    ) -> [String: String] {
        var env: [String: String] = [:]
        if let uid = testUserId { env[envKeyTestUserId] = uid }
        env[envKeyAnalyticsDisabled] = analyticsDisabled ? "1" : "0"
        return env
    }

    static func launchApp(
        _ app: XCUIApplication,
        uitest: Bool = true,
        skipOnboarding: Bool = false,
        quickSoloFirstSession: Bool = false,
        legacyOnboarding: Bool = false,
        seedTripWithTwoGames: Bool = false
    ) {
        app.launchArguments = launchArguments(
            uitest: uitest,
            skipOnboarding: skipOnboarding,
            quickSoloFirstSession: quickSoloFirstSession,
            legacyOnboarding: legacyOnboarding,
            seedTripWithTwoGames: seedTripWithTwoGames
        )
        app.launchEnvironment = launchEnvironment(analyticsDisabled: true)
        app.launch()
    }
}
