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

    // MARK: - COPPA F-7 (FR-33 amended): child sessions force all three flags off

    @Test func childForcedOff_killsAllThreeFlags() {
        let defaults = makeFreshDefaults()
        let service = LocationSettingsService(defaults: defaults)
        service.setChildSessionForcedOff(true)

        #expect(service.saveLocationWhenMarkingPlates == false)
        #expect(service.showMyLocationOnLargeMap == false)
        #expect(service.trackMyLocationDuringTrips == false)
        // Stored values are rewritten too, so raw UserDefaults readers agree.
        #expect(defaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates) == false)
        #expect(defaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap) == false)
        #expect(defaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips) == false)
    }

    @Test func childForcedOff_reappliesWhenAFlagFlipsBackOn() {
        let defaults = makeFreshDefaults()
        let service = LocationSettingsService(defaults: defaults)
        service.setChildSessionForcedOff(true)

        // Something flips a stored flag back on under a child session.
        defaults.set(true, forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)

        // The getter guard is the synchronous single source of truth, and the
        // didChange re-force rewrites storage immediately on the writing thread.
        #expect(service.saveLocationWhenMarkingPlates == false)
        #expect(defaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates) == false)
    }

    @Test func adultDefaultsUntouchedWhenNotForced() {
        // Owner decision D-11: adult factory defaults stay ON; only child sessions force.
        let service = LocationSettingsService(defaults: makeFreshDefaults())
        #expect(service.isChildSessionForcedOff == false)
        #expect(service.saveLocationWhenMarkingPlates == true)
        #expect(service.showMyLocationOnLargeMap == true)
        #expect(service.trackMyLocationDuringTrips == true)
    }

    @Test func liftingTheForceRestoresStoredReads() {
        // Correction path: force lifted; stored values (now false) govern again and
        // the user can re-enable manually. Defaults are not silently re-enabled.
        let defaults = makeFreshDefaults()
        let service = LocationSettingsService(defaults: defaults)
        service.setChildSessionForcedOff(true)
        service.setChildSessionForcedOff(false)
        #expect(service.saveLocationWhenMarkingPlates == false)
        defaults.set(true, forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        #expect(service.saveLocationWhenMarkingPlates == true)
    }
}
