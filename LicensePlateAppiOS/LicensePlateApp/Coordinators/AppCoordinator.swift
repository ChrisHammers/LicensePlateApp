//
//  AppCoordinator.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import Combine

/// Root-level coordinator for app flow: Splash → Force Update / Quick Start / Legacy Onboarding → Main App
@MainActor
final class AppCoordinator: ObservableObject {
    enum RootView: Equatable {
        case splash
        case forceUpdate
        case quickStart
        case legacyOnboarding
        case main
    }

    @Published var rootView: RootView = .splash
    @Published var pendingQuickSoloLaunch: QuickSoloLaunchIntent?

    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false

    init() {
        if AppLaunchConfiguration.skipOnboarding {
            hasSeenOnboarding = true
        }
    }

    // MARK: - Navigation Methods

    func showForceUpdate() {
        rootView = .forceUpdate
    }

    /// Transition from splash to next view (main, quick start, or legacy onboarding).
    func transitionFromSplash(quickSoloEnabled: Bool) {
        if hasSeenOnboarding {
            showMainApp()
            return
        }
        if AppLaunchConfiguration.forceLegacyOnboarding {
            showLegacyOnboarding()
            return
        }
        if quickSoloEnabled || AppLaunchConfiguration.forceQuickSoloFirstSession {
            showQuickStart()
        } else {
            showLegacyOnboarding()
        }
    }

    func showQuickStart() {
        rootView = .quickStart
    }

    func showLegacyOnboarding() {
        rootView = .legacyOnboarding
    }

    /// Complete legacy onboarding and show main app.
    func completeOnboarding() {
        hasSeenOnboarding = true
        pendingQuickSoloLaunch = nil
        showMainApp()
    }

    /// Complete quick start with auto-created trip; deep-link into gameplay from ContentView.
    func completeQuickStart(launchIntent: QuickSoloLaunchIntent) {
        hasSeenOnboarding = true
        pendingQuickSoloLaunch = launchIntent
        showMainApp()
    }

    func consumePendingQuickSoloLaunch() -> QuickSoloLaunchIntent? {
        let intent = pendingQuickSoloLaunch
        pendingQuickSoloLaunch = nil
        return intent
    }

    /// Show main app (ContentView)
    func showMainApp() {
        rootView = .main
    }
}
