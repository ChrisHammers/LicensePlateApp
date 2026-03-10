//
//  PendingTripsViewUITests.swift
//  LicensePlateAppUITests
//
//  Step 04 — UI tests for Pending Invites and Travel Log (inline sections on main screen).
//

import XCTest

final class PendingTripsViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainScreenShowsPendingInvitesSection() throws {
        let app = XCUIApplication()
        app.launch()

        // Pending Invites is now an inline section on the main screen
        let pendingInvitesHeader = app.staticTexts["Pending Invites"]
        XCTAssertTrue(pendingInvitesHeader.waitForExistence(timeout: 8), "Pending Invites section should be visible on main screen")
    }

    @MainActor
    func testMainScreenShowsTravelLogSection() throws {
        let app = XCUIApplication()
        app.launch()

        // Travel Log is now an inline section on the main screen
        let travelLogHeader = app.staticTexts["Travel Log"]
        XCTAssertTrue(travelLogHeader.waitForExistence(timeout: 8), "Travel Log section should be visible on main screen")
    }

    @MainActor
    func testMainScreenShowsActiveTripsSection() throws {
        let app = XCUIApplication()
        app.launch()

        let activeTripsHeader = app.staticTexts["Active Trips"]
        XCTAssertTrue(activeTripsHeader.waitForExistence(timeout: 8), "Active Trips section should be visible on main screen")
    }
}
