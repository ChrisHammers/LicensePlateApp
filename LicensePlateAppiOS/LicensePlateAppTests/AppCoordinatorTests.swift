//
//  AppCoordinatorTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AppCoordinatorTests {

    @Test func showForceUpdateSetsRoot() {
        let coordinator = AppCoordinator()
        coordinator.showForceUpdate()
        #expect(coordinator.rootView == .forceUpdate)
    }

    // F-6 (FR-27, owner placement): the root routes carry NO age gating — the age
    // question lives inside the flows (quick-start's pre-play step, legacy
    // onboarding's `.ageVerification` before account creation, sign-up's in-form
    // ask). The invariant is held by the provisioning guard (`GuestProvisioningPolicy`
    // + `signInAnonymously`), not by routing.

    @Test func transitionFromSplashShowsMainWhenOnboardingComplete() {
        let coordinator = AppCoordinator()
        coordinator.hasSeenOnboarding = true
        coordinator.transitionFromSplash(quickSoloEnabled: true)
        #expect(coordinator.rootView == .main)
    }

    @Test func transitionFromSplashShowsQuickStartWhenEnabled() {
        let coordinator = AppCoordinator()
        coordinator.hasSeenOnboarding = false
        coordinator.transitionFromSplash(quickSoloEnabled: true)
        #expect(coordinator.rootView == .quickStart)
    }

    @Test func transitionFromSplashShowsLegacyWhenQuickSoloDisabled() {
        let coordinator = AppCoordinator()
        coordinator.hasSeenOnboarding = false
        coordinator.transitionFromSplash(quickSoloEnabled: false)
        #expect(coordinator.rootView == .legacyOnboarding)
    }

    @Test func completeQuickStartStoresLaunchIntent() {
        let coordinator = AppCoordinator()
        let intent = QuickSoloLaunchIntent(sessionId: UUID(), gameId: UUID())
        coordinator.completeQuickStart(launchIntent: intent)
        #expect(coordinator.hasSeenOnboarding == true)
        #expect(coordinator.rootView == .main)
        #expect(coordinator.consumePendingQuickSoloLaunch() == intent)
        #expect(coordinator.consumePendingQuickSoloLaunch() == nil)
    }
}
