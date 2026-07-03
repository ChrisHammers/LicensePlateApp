//
//  TripSetupViewModel.swift
//  LicensePlateApp
//
//  Step 1 of new-trip flow: trip name, passengers, and trip settings.
//

import Foundation
import Combine

@MainActor
final class TripSetupViewModel: ObservableObject {
    @Published var tripName: String = ""
    @Published var startTripRightAway: Bool = false
    @Published var skipVoiceConfirmation: Bool = false
    @Published var holdToTalk: Bool = true
    @Published var saveLocationWhenMarkingPlates: Bool = true
    @Published var showMyLocationOnLargeMap: Bool = true
    @Published var trackMyLocationDuringTrip: Bool = true
    @Published var showMyActiveTripOnLargeMap: Bool = true
    @Published var showMyActiveTripOnSmallMap: Bool = true
    @Published var selectedPassengerIds: Set<String> = []

    @Published private(set) var shouldShowSetupAd = false

    private let authService: FirebaseAuthService

    init(
        authService: FirebaseAuthService,
        newTripDefaultsStore: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore()
    ) {
        self.authService = authService
        applyNewTripDefaults(newTripDefaultsStore.load())
    }

    func logSetupScreenAppeared() {
        AnalyticsService.shared.log(.tripSetupOpened)
        AnalyticsService.shared.logScreenView(screenName: "trip_setup")
        refreshAdEligibility()
    }

    func refreshAdEligibility() {
        shouldShowSetupAd = AdEligibilityService.shared.shouldShowAd(for: .tripSetup, user: authService.currentUser)
    }

    var canProceed: Bool { true }

    func buildDraft() -> TripSetupDraft {
        TripSetupDraft(
            tripName: tripName,
            selectedPassengerIds: selectedPassengerIds,
            startTripRightAway: startTripRightAway,
            skipVoiceConfirmation: skipVoiceConfirmation,
            holdToTalk: holdToTalk,
            saveLocationWhenMarkingPlates: saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: trackMyLocationDuringTrip,
            showMyActiveTripOnLargeMap: showMyActiveTripOnLargeMap,
            showMyActiveTripOnSmallMap: showMyActiveTripOnSmallMap
        )
    }

    private func applyNewTripDefaults(_ defaults: NewTripDefaults) {
        startTripRightAway = defaults.startTripRightAway
        skipVoiceConfirmation = defaults.skipVoiceConfirmation
        holdToTalk = defaults.holdToTalk
        saveLocationWhenMarkingPlates = defaults.saveLocationWhenMarkingPlates
        showMyLocationOnLargeMap = defaults.showMyLocationOnLargeMap
        trackMyLocationDuringTrip = defaults.trackMyLocationDuringTrip
        showMyActiveTripOnLargeMap = defaults.showMyActiveTripOnLargeMap
        showMyActiveTripOnSmallMap = defaults.showMyActiveTripOnSmallMap
    }
}
