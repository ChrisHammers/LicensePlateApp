//
//  LocationSettingsServiceTests.swift
//  LicensePlateAppTests
//

import Testing
import Foundation
@testable import LicensePlateApp

struct LocationSettingsServiceTests {

    /// Fresh suite with privacy bootstrap registered.
    private func makeFreshDefaults() -> UserDefaults {
        let name = "test.LocationSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        LocationSettingsBootstrap.registerFactoryDefaults(using: defaults)
        return defaults
    }

    @Test func privacyFlags_allTrueWhenUnset() {
        let service = LocationSettingsService(defaults: makeFreshDefaults())
        #expect(service.saveLocationWhenMarkingPlates == true)
        #expect(service.showMyLocationOnLargeMap == true)
        #expect(service.trackMyLocationDuringTrips == true)
    }

    @Test func globalOff_killsPrivacyFlag() {
        let defaults = makeFreshDefaults()
        defaults.set(false, forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        defaults.set(false, forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
        defaults.set(false, forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        let service = LocationSettingsService(defaults: defaults)
        #expect(service.saveLocationWhenMarkingPlates == false)
        #expect(service.showMyLocationOnLargeMap == false)
        #expect(service.trackMyLocationDuringTrips == false)
    }

    @Test func flags_areIndependentOfEachOther() {
        let defaults = makeFreshDefaults()
        defaults.set(false, forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        let service = LocationSettingsService(defaults: defaults)
        #expect(service.trackMyLocationDuringTrips == false)
        #expect(service.saveLocationWhenMarkingPlates == true)
        #expect(service.showMyLocationOnLargeMap == true)
    }

    @Test func bootstrap_doesNotOverwriteExplicitUserValues() {
        let defaults = makeFreshDefaults()
        defaults.set(false, forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        LocationSettingsBootstrap.registerFactoryDefaults(using: defaults)
        let service = LocationSettingsService(defaults: defaults)
        #expect(service.saveLocationWhenMarkingPlates == false)
    }
}
