//
//  LicensePlateAppUITests.swift
//  LicensePlateAppUITests
//
//  Created by Christopher Hammers on 11/11/25.
//

import XCTest

final class LicensePlateAppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Step 13 — Launch with --uitest and verify app launches. When app supports seed flags, extend to assert on seeded content.
    @MainActor
    func testLaunchWithUITestFlag() throws {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunchHelper.launchArguments(uitest: true, skipOnboarding: false)
        app.launchEnvironment = UITestLaunchHelper.launchEnvironment(analyticsDisabled: true)
        app.launch()
        XCTAssertTrue(app.exists, "App should launch")
    }
}
