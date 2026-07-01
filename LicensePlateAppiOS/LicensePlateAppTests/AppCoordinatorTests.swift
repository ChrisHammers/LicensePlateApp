//
//  AppCoordinatorTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

@MainActor
struct AppCoordinatorTests {

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
