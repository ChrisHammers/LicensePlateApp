//
//  PendingTripsViewUITests.swift
//  LicensePlateAppUITests
//
//  Step 04 — UI tests for Pending Invites and Travel Log (inline sections on main screen).
//
//  Every test launches with `--skipOnboarding` so a fresh simulator lands on Home instead of the
//  age gate / onboarding, and waits out the real startup chain (see `UITestLaunchHelper.startupTimeout`).
//

import XCTest

final class PendingTripsViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainScreenShowsPendingInvitesSection() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, skipOnboarding: true)

        // Pending Invites is an inline section on the main screen (header renders in both the
        // empty and populated states).
        let pendingInvitesHeader = app.staticTexts["Pending Invites"]
        XCTAssertTrue(
            pendingInvitesHeader.waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Pending Invites section should be visible on main screen"
        )
    }

    @MainActor
    func testMainScreenShowsTravelLogSection() throws {
        let app = XCUIApplication()
        UITestLaunchHelper.launchApp(app, skipOnboarding: true)

        // Open Travel Log via toolbar map button; sheet shows "Travel Log" title or empty state
        let mapButton = app.buttons["Travel Log"]
        XCTAssertTrue(
            mapButton.waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Travel Log toolbar button should exist"
        )
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
        UITestLaunchHelper.launchApp(app, skipOnboarding: true)

        let activeTripsHeader = app.staticTexts["Active Trips"]
        XCTAssertTrue(
            activeTripsHeader.waitForExistence(timeout: UITestLaunchHelper.startupTimeout),
            "Active Trips section should be visible on main screen"
        )
    }
}
