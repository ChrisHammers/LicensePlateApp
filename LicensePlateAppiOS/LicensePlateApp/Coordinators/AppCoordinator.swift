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
            // QA/UI-test override only: skipping onboarding also seeds an adult age
            // answer so a fresh-simulator launch provisions its guest immediately and
            // lands on main. Protective direction preserved — an existing under-13
            // answer is never overwritten (AgeGateStore rule).
            if !AgeGateStore.shared.isResolved {
                AgeGateStore.shared.recordAnswer(.teenAdult)
            }
        }
    }

    // MARK: - Navigation Methods

    func showForceUpdate() {
        rootView = .forceUpdate
    }

    /// Transition from splash to next view (main, quick start, or legacy onboarding).
    /// F-6 (FR-27): no root-level age gating — the age question lives INSIDE the flows,
    /// after their intro content and immediately before provisioning begins
    /// (quick-start asks at the play tap; legacy onboarding's `.ageVerification` step
    /// precedes account creation; sign-up asks in-form). The FR-27 invariant is held by
    /// the provisioning guard, not by routing: no anonymous uid or users/{uid} write
    /// exists until an epoch answer does.
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
