//
//  AppPrefsStoreTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AppPrefsStoreTests {

    private func makeFreshDefaults() -> UserDefaults {
        let name = "test.AppPrefsStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        NewTripDefaultsBootstrap.registerFactoryDefaults(using: defaults)
        return defaults
    }

    @Test func resetToDefaultsClearsInMemoryCache() {
        let defaults = makeFreshDefaults()
        let localStore = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let store = AppPrefsStore(
            userRepository: .shared,
            localDefaultsStore: localStore
        )
        store.apply(
            UserRepository.GameDefaults(
                includeUS: false,
                includeCanada: false,
                includeMexico: true,
                startTripRightAway: false
            )
        )
        #expect(store.gameDefaults.includeUS == false)
        store.resetToDefaults()
        #expect(store.gameDefaults == .default)
    }

    @Test func applyDoesNotRequireCloud() {
        let defaults = makeFreshDefaults()
        let localStore = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let store = AppPrefsStore(
            userRepository: .shared,
            localDefaultsStore: localStore
        )
        let cloud = UserRepository.GameDefaults(
            includeUS: false,
            includeCanada: true,
            includeMexico: false,
            startTripRightAway: false
        )
        store.apply(cloud)
        #expect(store.gameDefaults == cloud)
    }

    @Test func viewModelSaveWithoutUserIdStaysLocalOnly() async {
        let defaults = makeFreshDefaults()
        let localStore = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let appPrefs = AppPrefsStore(
            userRepository: .shared,
            localDefaultsStore: localStore
        )
        let vm = NewTripDefaultsViewModel(store: localStore, appPrefsStore: appPrefs)
        vm.configure(userId: nil)
        vm.includeUS = false
        vm.includeCanada = true
        vm.includeMexico = false
        vm.startTripRightAway = false
        await vm.save()

        let loaded = localStore.load()
        #expect(loaded.includeUS == false)
        #expect(loaded.includeCanada == true)
        #expect(loaded.includeMexico == false)
        #expect(loaded.startTripRightAway == false)
        // Guest path does not push into the in-memory cloud cache.
        #expect(appPrefs.gameDefaults == .default)
    }

    @Test func viewModelSavePersistsLocalCloudFields() async {
        let defaults = makeFreshDefaults()
        let localStore = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let appPrefs = AppPrefsStore(
            userRepository: .shared,
            localDefaultsStore: localStore
        )
        let vm = NewTripDefaultsViewModel(store: localStore, appPrefsStore: appPrefs)
        // Empty userId keeps guest/local path (no Firestore).
        vm.configure(userId: "")
        vm.includeUS = false
        vm.startTripRightAway = false
        await vm.save()

        let loaded = localStore.load()
        #expect(loaded.includeUS == false)
        #expect(loaded.startTripRightAway == false)
    }
}
