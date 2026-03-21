//
//  NewTripDefaultsTests.swift
//  LicensePlateAppTests
//

import Testing
import Foundation
@testable import LicensePlateApp

@MainActor
struct NewTripDefaultsTests {

    private func makeFreshDefaults() -> UserDefaults {
        let name = "test.NewTripDefaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        NewTripDefaultsBootstrap.registerFactoryDefaults(using: defaults)
        return defaults
    }

    @Test func bootstrap_startTripRightAwayTrueWhenUnset() {
        let defaults = makeFreshDefaults()
        #expect(defaults.bool(forKey: NewTripDefaultsKeys.startTripRightAway) == true)
    }

    @Test func store_roundTrip() {
        let defaults = makeFreshDefaults()
        let store = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        var s = store.load()
        s.includeUS = false
        s.includeCanada = true
        s.includeMexico = false
        store.save(s)
        let loaded = store.load()
        #expect(loaded.includeUS == false)
        #expect(loaded.includeCanada == true)
        #expect(loaded.includeMexico == false)
    }

    @Test func viewModel_canSave_requiresOneCountry() {
        let defaults = makeFreshDefaults()
        let store = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let vm = NewTripDefaultsViewModel(store: store)
        vm.includeUS = false
        vm.includeCanada = false
        vm.includeMexico = false
        #expect(vm.canSave == false)
        vm.includeMexico = true
        #expect(vm.canSave == true)
    }

    @Test func viewModel_save_persistsForNextInit() {
        let defaults = makeFreshDefaults()
        let store = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let vm = NewTripDefaultsViewModel(store: store)
        vm.includeUS = false
        vm.includeCanada = true
        vm.includeMexico = false
        vm.save()
        let vm2 = NewTripDefaultsViewModel(store: store)
        #expect(vm2.includeUS == false)
        #expect(vm2.includeCanada == true)
        #expect(vm2.includeMexico == false)
    }

    @Test func viewModel_reloadFromStore_discardsUnsavedEdits() {
        let defaults = makeFreshDefaults()
        let store = UserDefaultsNewTripDefaultsStore(defaults: defaults)
        let vm = NewTripDefaultsViewModel(store: store)
        vm.includeUS = false
        vm.save()
        vm.includeUS = true
        vm.reloadFromStore()
        #expect(vm.includeUS == false)
    }
}
