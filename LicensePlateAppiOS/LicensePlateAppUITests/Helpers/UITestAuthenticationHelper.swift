//
//  UITestAuthenticationHelper.swift
//  LicensePlateAppUITests
//
//  Step 13 — Placeholder for test auth (bypass or set test user via launch env).
//

import Foundation
import XCTest

/// Intended usage: set UITestLaunchHelper.envKeyTestUserId in app.launchEnvironment to a fixed user id
/// so the app (when built with test-only code path for --uitest) can skip real auth and use that user.
/// This helper documents the contract; actual bypass must be implemented in the app when needed.
enum UITestAuthenticationHelper {
    /// Default test user id when app supports UITEST_USER_ID launch environment.
    static let defaultTestUserId = "uitest-user-1"

    /// Read test user id from launch environment (for use inside the app, not in UI test target).
    static func testUserId(from environment: [String: String]) -> String? {
        environment[UITestLaunchHelper.envKeyTestUserId]
    }
}
