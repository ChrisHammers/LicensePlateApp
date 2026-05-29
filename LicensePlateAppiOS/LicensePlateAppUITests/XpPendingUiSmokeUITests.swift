//
//  XpPendingUiSmokeUITests.swift
//  LicensePlateAppUITests
//

import XCTest

final class XpPendingUiSmokeUITests: XCTestCase {

    @MainActor
    func testLaunchSmoke() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
