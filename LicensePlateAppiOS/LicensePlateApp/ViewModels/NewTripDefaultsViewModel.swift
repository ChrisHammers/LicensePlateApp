//
//  NewTripDefaultsViewModel.swift
//  LicensePlateApp
//

import Foundation
import Combine

@MainActor
final class NewTripDefaultsViewModel: ObservableObject {
    @Published var includeUS: Bool
    @Published var includeCanada: Bool
    @Published var includeMexico: Bool
    @Published var startTripRightAway: Bool
    @Published var skipVoiceConfirmation: Bool
    @Published var holdToTalk: Bool
    @Published var saveLocationWhenMarkingPlates: Bool
    @Published var showMyLocationOnLargeMap: Bool
    @Published var trackMyLocationDuringTrip: Bool
    @Published var showMyActiveTripOnLargeMap: Bool
    @Published var showMyActiveTripOnSmallMap: Bool

    private let store: NewTripDefaultsStoring

    init(store: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore()) {
        self.store = store
        let s = store.load()
        includeUS = s.includeUS
        includeCanada = s.includeCanada
        includeMexico = s.includeMexico
        startTripRightAway = s.startTripRightAway
        skipVoiceConfirmation = s.skipVoiceConfirmation
        holdToTalk = s.holdToTalk
        saveLocationWhenMarkingPlates = s.saveLocationWhenMarkingPlates
        showMyLocationOnLargeMap = s.showMyLocationOnLargeMap
        trackMyLocationDuringTrip = s.trackMyLocationDuringTrip
        showMyActiveTripOnLargeMap = s.showMyActiveTripOnLargeMap
        showMyActiveTripOnSmallMap = s.showMyActiveTripOnSmallMap
    }

    var canSave: Bool {
        !enabledCountries.isEmpty
    }

    var countryValidationMessage: String? {
        !enabledCountries.isEmpty ? nil : "Select at least one country.".localized
    }
    
    var enabledCountries: [PlateRegion.Country] {
        var list: [PlateRegion.Country] = []
        if includeUS { list.append(.unitedStates) }
        if includeCanada { list.append(.canada) }
        if includeMexico { list.append(.mexico) }
        return list
    }

    func reloadFromStore() {
        let s = store.load()
        includeUS = s.includeUS
        includeCanada = s.includeCanada
        includeMexico = s.includeMexico
        startTripRightAway = s.startTripRightAway
        skipVoiceConfirmation = s.skipVoiceConfirmation
        holdToTalk = s.holdToTalk
        saveLocationWhenMarkingPlates = s.saveLocationWhenMarkingPlates
        showMyLocationOnLargeMap = s.showMyLocationOnLargeMap
        trackMyLocationDuringTrip = s.trackMyLocationDuringTrip
        showMyActiveTripOnLargeMap = s.showMyActiveTripOnLargeMap
        showMyActiveTripOnSmallMap = s.showMyActiveTripOnSmallMap
    }

    func snapshot() -> NewTripDefaults {
        NewTripDefaults(
            includeUS: includeUS,
            includeCanada: includeCanada,
            includeMexico: includeMexico,
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

    func save() {
        store.save(snapshot())
    }
}
