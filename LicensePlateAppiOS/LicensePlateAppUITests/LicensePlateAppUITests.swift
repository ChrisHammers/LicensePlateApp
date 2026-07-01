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
        XCTAssertTrue(app.staticTexts["RoadTrip Royale"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLegacyOnboardingShowsWelcome() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, legacyOnboarding: true)
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testQuickSoloStartScreenWhenForced() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, quickSoloFirstSession: true)
        XCTAssertTrue(app.buttons["Start Quick Solo Trip"].waitForExistence(timeout: 8))
    }
}
