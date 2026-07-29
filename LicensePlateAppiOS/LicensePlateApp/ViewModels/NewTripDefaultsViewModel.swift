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
    private let appPrefsStore: AppPrefsStore
    private var userId: String?

    init(
        store: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore(),
        appPrefsStore: AppPrefsStore = .shared
    ) {
        self.store = store
        self.appPrefsStore = appPrefsStore
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

    func configure(userId: String?) {
        self.userId = userId
    }

    /// Hydrate cloud game defaults (when signed in), then reload the full local snapshot into UI.
    func loadIfNeeded() async {
        if let userId, !userId.isEmpty {
            await appPrefsStore.load(userId: userId)
        }
        reloadFromStore()
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

    /// Persists full snapshot to UserDefaults; when signed in, also pushes the four cloud fields.
    func save() async {
        let snap = snapshot()
        store.save(snap)
        guard let userId, !userId.isEmpty else { return }
        let cloud = UserRepository.GameDefaults(
            includeUS: snap.includeUS,
            includeCanada: snap.includeCanada,
            includeMexico: snap.includeMexico,
            startTripRightAway: snap.startTripRightAway
        )
        await appPrefsStore.save(userId: userId, defaults: cloud)
    }
}
