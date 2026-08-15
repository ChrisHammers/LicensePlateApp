//
//  AppLaunchConfiguration.swift
//  LicensePlateApp
//
//  Launch arguments for UI tests and QA overrides.
//

import Foundation

enum AppLaunchConfiguration {
    static let launchArgUITest = "--uitest"
    static let launchArgSkipOnboarding = "--skipOnboarding"
    static let launchArgQuickSoloFirstSession = "--quickSoloFirstSession"
    static let launchArgLegacyOnboarding = "--legacyOnboarding"

    static var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgUITest)
    }

    static var skipOnboarding: Bool {
        // QA/UI-test override only (COPPA FR-83a): also seeds an age-gate bypass in
        // AppCoordinator, so this must never evaluate true in a release binary.
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(launchArgSkipOnboarding)
        #else
        false
        #endif
    }

    static var forceQuickSoloFirstSession: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgQuickSoloFirstSession)
    }

    static var forceLegacyOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgLegacyOnboarding)
    }
}
