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
