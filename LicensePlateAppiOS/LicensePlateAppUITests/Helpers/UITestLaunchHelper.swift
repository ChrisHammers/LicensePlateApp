//
//  UITestLaunchHelper.swift
//  LicensePlateAppUITests
//
//  Step 13 — Launch app with optional arguments/environment for UI tests.
//

import XCTest

/// Use launch arguments or environment so the app can enable test-only behavior (e.g. skip onboarding, seed data).
/// Configure in test: app.launchArguments = UITestLaunchHelper.launchArguments(uitest: true, skipOnboarding: true)
enum UITestLaunchHelper {
    static let launchArgUITest = "--uitest"
    static let launchArgSkipOnboarding = "--skipOnboarding"
    static let launchArgSeedTripWithTwoGames = "--seedTripWithTwoGames"
    static let launchArgSeedCollaborativeTrip = "--seedCollaborativeTrip"
    static let launchArgSeedTripWithRiskFlags = "--seedTripWithRiskFlags"

    static let envKeyTestUserId = "UITEST_USER_ID"
    static let envKeyAnalyticsDisabled = "UITEST_ANALYTICS_DISABLED"

    /// Build launch arguments for XCUIApplication. Pass these to app.launchArguments before app.launch().
    static func launchArguments(
        uitest: Bool = true,
        skipOnboarding: Bool = false,
        seedTripWithTwoGames: Bool = false,
        seedCollaborativeTrip: Bool = false,
        seedTripWithRiskFlags: Bool = false
    ) -> [String] {
        var args: [String] = []
        if uitest { args.append(launchArgUITest) }
        if skipOnboarding { args.append(launchArgSkipOnboarding) }
        if seedTripWithTwoGames { args.append(launchArgSeedTripWithTwoGames) }
        if seedCollaborativeTrip { args.append(launchArgSeedCollaborativeTrip) }
        if seedTripWithRiskFlags { args.append(launchArgSeedTripWithRiskFlags) }
        return args
    }

    /// Build launch environment for XCUIApplication. App can read these to e.g. set test user or disable analytics.
    static func launchEnvironment(
        testUserId: String? = nil,
        analyticsDisabled: Bool = true
    ) -> [String: String] {
        var env: [String: String] = [:]
        if let uid = testUserId { env[envKeyTestUserId] = uid }
        env[envKeyAnalyticsDisabled] = analyticsDisabled ? "1" : "0"
        return env
    }

    /// Launch the given app with common UI test args and environment. Call from test's setUp or test method.
    static func launchApp(
        _ app: XCUIApplication,
        uitest: Bool = true,
        skipOnboarding: Bool = false,
        seedTripWithTwoGames: Bool = false
    ) {
        app.launchArguments = launchArguments(
            uitest: uitest,
            skipOnboarding: skipOnboarding,
            seedTripWithTwoGames: seedTripWithTwoGames
        )
        app.launchEnvironment = launchEnvironment(analyticsDisabled: true)
        app.launch()
    }
}
