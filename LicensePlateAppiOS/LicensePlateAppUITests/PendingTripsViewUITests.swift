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

        // Open Travel Log via toolbar map button; sheet shows "Travel Log" title or empty state
        let mapButton = app.buttons["Travel Log Invites"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 8), "Travel Log toolbar button should exist")
        mapButton.tap()
        let travelLogTitle = app.navigationBars["Travel Log"].firstMatch
        let noTripsText = app.staticTexts["No completed trips yet"]
        XCTAssertTrue(
            travelLogTitle.waitForExistence(timeout: 4) || noTripsText.waitForExistence(timeout: 4),
            "Travel Log sheet should show title or empty state"
        )
    }

    @MainActor
    func testMainScreenShowsActiveTripsSection() throws {
        let app = XCUIApplication()
        app.launch()

        let activeTripsHeader = app.staticTexts["Active Trips"]
        XCTAssertTrue(activeTripsHeader.waitForExistence(timeout: 8), "Active Trips section should be visible on main screen")
    }
}
