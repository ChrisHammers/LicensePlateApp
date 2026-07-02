//
//  TripSetupViewModel.swift
//  LicensePlateApp
//
//  Step 1 of new-trip flow: trip name, passengers, countries, and trip settings.
//

import Foundation
import Combine

@MainActor
final class TripSetupViewModel: ObservableObject {
    @Published var tripName: String = ""
    @Published var includeUS: Bool = true
    @Published var includeCanada: Bool = true
    @Published var includeMexico: Bool = true
    @Published var includeUSTerritories: Bool = true
    @Published var includeDC: Bool = true
    @Published var includeCanadianTerritories: Bool = true
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

    var enabledCountries: [PlateRegion.Country] {
        var list: [PlateRegion.Country] = []
        if includeUS { list.append(.unitedStates) }
        if includeCanada { list.append(.canada) }
        if includeMexico { list.append(.mexico) }
        return list
    }

    var canProceed: Bool {
        !enabledCountries.isEmpty
    }

    var countryValidationMessage: String? {
        enabledCountries.isEmpty ? "Select at least one country.".localized : nil
    }

    func applyTerritoryGatingFromCountryToggles() {
        if !includeUS {
            includeUSTerritories = false
            includeDC = false
        }
        if !includeCanada {
            includeCanadianTerritories = false
        }
    }

    func buildDraft() -> TripSetupDraft {
        applyTerritoryGatingFromCountryToggles()
        return TripSetupDraft(
            tripName: tripName,
            selectedPassengerIds: selectedPassengerIds,
            enabledCountries: enabledCountries,
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: includeUSTerritories,
                includeCanadianTerritories: includeCanadianTerritories,
                includeDC: includeDC
            ),
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
        includeUS = defaults.includeUS
        includeCanada = defaults.includeCanada
        includeMexico = defaults.includeMexico
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
