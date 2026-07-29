//
//  GameDefaultsTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameDefaultsTests {
    @Test func fromFirestoreMapUsesDefaultsForMissingKeys() {
        let defaults = UserRepository.GameDefaults.fromFirestoreMap(nil)
        #expect(defaults == .default)
        #expect(defaults.includeUS == true)
        #expect(defaults.includeCanada == true)
        #expect(defaults.includeMexico == true)
        #expect(defaults.startTripRightAway == true)
    }

    @Test func fromFirestoreMapReadsKnownBooleans() {
        let defaults = UserRepository.GameDefaults.fromFirestoreMap([
            "includeUS": false,
            "includeMexico": false,
            "ignored": "x"
        ])
        #expect(defaults.includeUS == false)
        #expect(defaults.includeCanada == true)
        #expect(defaults.includeMexico == false)
        #expect(defaults.startTripRightAway == true)
    }

    @Test func firestoreMapIncludesAllKeys() {
        let map = UserRepository.GameDefaults.default.firestoreMap
        #expect(map.count == 4)
        #expect(map["includeUS"] == true)
        #expect(map["includeCanada"] == true)
        #expect(map["includeMexico"] == true)
        #expect(map["startTripRightAway"] == true)
    }

    @Test func firestoreMapReflectsMutations() {
        var defaults = UserRepository.GameDefaults.default
        defaults.includeUS = false
        defaults.startTripRightAway = false
        let map = defaults.firestoreMap
        #expect(map["includeUS"] == false)
        #expect(map["startTripRightAway"] == false)
        #expect(map["includeCanada"] == true)
    }
}
