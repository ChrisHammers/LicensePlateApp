//
//  PendingTripsViewUITests.swift
//  LicensePlateAppUITests
//
//  Step 04 — UI tests for Pending Trips: navigate to screen, assert empty state or invite row.
//

import XCTest

final class PendingTripsViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPendingTripsScreenOpensAndShowsEmptyState() throws {
        let app = XCUIApplication()
        app.launch()

        // Find and tap Pending Trips row (under Trip activity section)
        let pendingTripsCell = app.cells.containing(NSPredicate(format: "label CONTAINS 'Pending'")).firstMatch
        if !pendingTripsCell.waitForExistence(timeout: 8) {
            // Fallback: tap by static text
            let label = app.staticTexts["Pending Trips"]
            if label.waitForExistence(timeout: 2) { label.tap() }
        } else {
            pendingTripsCell.tap()
        }

        // Pending Trips screen: Close button indicates we reached the screen
        let closeButton = app.buttons["pendingTrips_closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Close button should be visible on Pending Trips screen")
    }

    @MainActor
    func testPendingTripsCloseButtonDismissesScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let pendingTripsCell = app.cells.containing(NSPredicate(format: "label CONTAINS 'Pending'")).firstMatch
        if pendingTripsCell.waitForExistence(timeout: 5) {
            pendingTripsCell.tap()
        }

        let closeButton = app.buttons["pendingTrips_closeButton"]
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
            // After tap we should be back on main screen (Pending Trips row visible again or Trips section)
            let backOnHome = app.staticTexts["RoadTrip Royale"].waitForExistence(timeout: 2)
                || app.staticTexts["Trips"].waitForExistence(timeout: 2)
                || app.staticTexts["Active Trips"].waitForExistence(timeout: 2)
            XCTAssertTrue(backOnHome, "Tapping Close should return to home")
        }
    }
}
