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
        ProcessInfo.processInfo.arguments.contains(launchArgSkipOnboarding)
    }

    static var forceQuickSoloFirstSession: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgQuickSoloFirstSession)
    }

    static var forceLegacyOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgLegacyOnboarding)
    }
}
