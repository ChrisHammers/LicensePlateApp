//
//  AppPrefsStore.swift
//  LicensePlateApp
//
//  In-memory cache of Firestore appPrefs.gameDefaults for Settings + setup hydrate.
//  UserDefaults remains the local cache read by GameSetup / TripSetup / QuickSolo.
//

import Foundation
import Combine

@MainActor
protocol AppPrefsReading: AnyObject {
    var gameDefaults: UserRepository.GameDefaults { get }
}

@MainActor
final class AppPrefsStore: ObservableObject, AppPrefsReading {
    static let shared = AppPrefsStore()

    @Published private(set) var gameDefaults: UserRepository.GameDefaults = .default
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

    func apply(_ defaults: UserRepository.GameDefaults) {
        gameDefaults = defaults
    }

    /// Hard sign-out: drop cached account prefs (local UserDefaults left for guest).
    func resetToDefaults() {
        gameDefaults = .default
        loadedUserId = nil
        lastErrorMessage = nil
        isLoading = false
    }

    /// Load from Firestore into the cache and write-through the four cloud fields to UserDefaults.
    /// If the cloud map is absent, upload current local UserDefaults values once (migration).
    func load(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await userRepository.fetchGameDefaults(userId: userId)
            if result.cloudMapPresent {
                gameDefaults = result.defaults
                writeThroughToLocalCache(result.defaults)
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
                writeThroughToLocalCache(migrated)
            }
            loadedUserId = userId
        } catch {
            lastErrorMessage = error.localizedDescription
            // Keep last known / defaults when offline; still mirror cache if we have in-memory values.
        }
    }

    /// Persist full gameDefaults map, update cache, and write-through to UserDefaults.
    func save(userId: String, defaults: UserRepository.GameDefaults) async {
        guard !userId.isEmpty else { return }
        gameDefaults = defaults
        loadedUserId = userId
        writeThroughToLocalCache(defaults)
        do {
            try await userRepository.updateGameDefaults(userId: userId, defaults: defaults)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Updates only the four cloud-synced keys in the local New Trip Defaults cache.
    private func writeThroughToLocalCache(_ defaults: UserRepository.GameDefaults) {
        var snapshot = localDefaultsStore.load()
        snapshot.includeUS = defaults.includeUS
        snapshot.includeCanada = defaults.includeCanada
        snapshot.includeMexico = defaults.includeMexico
        snapshot.startTripRightAway = defaults.startTripRightAway
        localDefaultsStore.save(snapshot)
    }
}
