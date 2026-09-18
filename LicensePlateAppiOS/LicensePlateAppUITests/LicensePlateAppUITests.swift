//
//  LicensePlateAppUITests.swift
//  LicensePlateAppUITests
//
//  Created by Christopher Hammers on 11/11/25.
//

import XCTest

final class LicensePlateAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchWithUITestFlag() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunchHelper.launchArguments(uitest: true, skipOnboarding: false)
        app.launchEnvironment = UITestLaunchHelper.launchEnvironment(analyticsDisabled: true)
        app.launch()
        XCTAssertTrue(app.exists, "App should launch")
    }

    @MainActor
    func testSkipOnboardingShowsHome() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, skipOnboarding: true)
        // "RoadTrip Royale" is also the splash title, so it cannot prove Home was reached; the
        // "Active Trips" section header exists only on Home (rendered in both its empty and
        // populated states).
        XCTAssertTrue(
            app.staticTexts["Active Trips"].waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Home should show after the splash when onboarding is skipped"
        )
    }

    @MainActor
    func testLegacyOnboardingShowsWelcome() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, legacyOnboarding: true)
        XCTAssertTrue(
            app.buttons["Get Started"].waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Legacy onboarding should open on the Welcome step after the splash"
        )
    }

    @MainActor
    func testQuickSoloStartScreenWhenForced() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, quickSoloFirstSession: true)
        XCTAssertTrue(
            app.buttons["Start Quick Solo Trip"].waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Quick-solo start screen should show after the splash when forced"
        )
    }
}
