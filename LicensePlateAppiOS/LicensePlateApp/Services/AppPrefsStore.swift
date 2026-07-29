//
//  AppPrefsStore.swift
//  LicensePlateApp
//
//  In-memory cache of Firestore appPrefs (gameDefaults + participationDefaults).
//  UserDefaults remains the local cache read by setup / New Trip Defaults.
//

import Foundation
import Combine

@MainActor
protocol AppPrefsReading: AnyObject {
    var gameDefaults: UserRepository.GameDefaults { get }
    var participationDefaults: ParticipationDefaults { get }
}

@MainActor
final class AppPrefsStore: ObservableObject, AppPrefsReading {
    static let shared = AppPrefsStore()

    @Published private(set) var gameDefaults: UserRepository.GameDefaults = .default
    @Published private(set) var participationDefaults: ParticipationDefaults = .default
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let userRepository: UserRepository
    private let localDefaultsStore: UserDefaultsNewTripDefaultsStore
    private var loadedUserId: String?

    init(
        userRepository: UserRepository = .shared,
        localDefaultsStore: UserDefaultsNewTripDefaultsStore = UserDefaultsNewTripDefaultsStore()
    ) {
        self.userRepository = userRepository
        self.localDefaultsStore = localDefaultsStore
    }

    func applyGameDefaults(_ defaults: UserRepository.GameDefaults) {
        gameDefaults = defaults
    }

    func applyParticipationDefaults(_ defaults: ParticipationDefaults) {
        participationDefaults = defaults
    }

    /// Hard sign-out: drop cached account prefs (local UserDefaults left for guest).
    func resetToDefaults() {
        gameDefaults = .default
        participationDefaults = .default
        loadedUserId = nil
        lastErrorMessage = nil
        isLoading = false
    }

    /// Load from Firestore into the cache and write-through to UserDefaults.
    /// Missing cloud maps are migrated once from local UserDefaults.
    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }
        do {
            let gameResult = try await userRepository.fetchGameDefaults(userId: userId)
            if gameResult.cloudMapPresent {
                gameDefaults = gameResult.defaults
                writeThroughGameDefaults(gameResult.defaults)
            } else {
                let local = localDefaultsStore.load()
                let migrated = UserRepository.GameDefaults(
                    includeUS: local.includeUS,
                    includeCanada: local.includeCanada,
                    includeMexico: local.includeMexico,
                    startTripRightAway: local.startTripRightAway
                )
                gameDefaults = migrated
                try await userRepository.updateGameDefaults(userId: userId, defaults: migrated)
                writeThroughGameDefaults(migrated)
            }

            let partResult = try await userRepository.fetchParticipationDefaults(userId: userId)
            if partResult.cloudMapPresent {
                participationDefaults = partResult.defaults
                writeThroughParticipationDefaults(partResult.defaults)
            } else {
                let local = localDefaultsStore.load()
                let migrated = ParticipationDefaults(
                    skipVoiceConfirmation: local.skipVoiceConfirmation,
                    saveLocationWhenMarkingPlates: local.saveLocationWhenMarkingPlates,
                    showMyLocationOnLargeMap: local.showMyLocationOnLargeMap,
                    trackMyLocationDuringTrip: local.trackMyLocationDuringTrip
                )
                participationDefaults = migrated
                try await userRepository.updateParticipationDefaults(userId: userId, defaults: migrated)
                writeThroughParticipationDefaults(migrated)
            }

            loadedUserId = userId
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveGameDefaults(userId: String, defaults: UserRepository.GameDefaults) async {
        guard !userId.isEmpty else { return }
        gameDefaults = defaults
        loadedUserId = userId
        writeThroughGameDefaults(defaults)
        do {
            try await userRepository.updateGameDefaults(userId: userId, defaults: defaults)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveParticipationDefaults(userId: String, defaults: ParticipationDefaults) async {
        guard !userId.isEmpty else { return }
        participationDefaults = defaults
        loadedUserId = userId
        writeThroughParticipationDefaults(defaults)
        do {
            try await userRepository.updateParticipationDefaults(userId: userId, defaults: defaults)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Convenience: persist both maps from a full NewTripDefaults snapshot when signed in.
    func save(userId: String, defaults: UserRepository.GameDefaults) async {
        await saveGameDefaults(userId: userId, defaults: defaults)
    }

    private func writeThroughGameDefaults(_ defaults: UserRepository.GameDefaults) {
        var snapshot = localDefaultsStore.load()
        snapshot.includeUS = defaults.includeUS
        snapshot.includeCanada = defaults.includeCanada
        snapshot.includeMexico = defaults.includeMexico
        snapshot.startTripRightAway = defaults.startTripRightAway
        localDefaultsStore.save(snapshot)
    }

    private func writeThroughParticipationDefaults(_ defaults: ParticipationDefaults) {
        var snapshot = localDefaultsStore.load()
        snapshot.skipVoiceConfirmation = defaults.skipVoiceConfirmation
        snapshot.saveLocationWhenMarkingPlates = defaults.saveLocationWhenMarkingPlates
        snapshot.showMyLocationOnLargeMap = defaults.showMyLocationOnLargeMap
        snapshot.trackMyLocationDuringTrip = defaults.trackMyLocationDuringTrip
        localDefaultsStore.save(snapshot)
    }
}
