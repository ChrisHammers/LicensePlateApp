//
//  TravelLogViewUITests.swift
//  LicensePlateAppUITests
//
//  Step 07 — UI tests: open Travel Log from toolbar, assert sheet shows title or content.
//
//  Launches with `--skipOnboarding` so a fresh simulator lands on Home instead of the age gate /
//  onboarding, and waits out the real startup chain (see `UITestLaunchHelper.startupTimeout`).
//

import XCTest

final class TravelLogViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningTravelLogSheetShowsTravelLogTitle() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, skipOnboarding: true)

        // Tap toolbar map button to open Travel Log sheet
        let mapButton = app.buttons["Travel Log"]
        XCTAssertTrue(
            mapButton.waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Toolbar map button (Travel Log) should exist"
        )
        mapButton.tap()

        // Sheet should show "Travel Log" as title or empty state text
        let travelLogTitle = app.navigationBars["Travel Log"].firstMatch
        let noTripsText = app.staticTexts["No completed trips yet"]
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(
            travelLogTitle.waitForExistence(timeout: 4) || noTripsText.waitForExistence(timeout: 4) || closeButton.waitForExistence(timeout: 4),
            "Travel Log sheet should show title, empty state, or Close button"
        )
    }
}
