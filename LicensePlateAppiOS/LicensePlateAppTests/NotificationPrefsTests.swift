//
//  NotificationPrefsTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct NotificationPrefsTests {
    @Test func fromFirestoreMapUsesDefaultsForMissingKeys() {
        let prefs = UserRepository.NotificationPrefs.fromFirestoreMap(nil)
        #expect(prefs == .default)
        #expect(prefs.promotionsAndNews == false)
        #expect(prefs.friend == true)
    }

    @Test func fromFirestoreMapReadsKnownBooleans() {
        let prefs = UserRepository.NotificationPrefs.fromFirestoreMap([
            "friend": false,
            "tripInvite": false,
            "promotionsAndNews": true,
            "ignored": "x"
        ])
        #expect(prefs.friend == false)
        #expect(prefs.tripInvite == false)
        #expect(prefs.family == true)
        #expect(prefs.promotionsAndNews == true)
        #expect(prefs.plateFoundByOpponent == true)
    }

    @Test func firestoreMapIncludesAllKeys() {
        let map = UserRepository.NotificationPrefs.default.firestoreMap
        #expect(map.count == 9)
        #expect(map["friend"] == true)
        #expect(map["promotionsAndNews"] == false)
        #expect(map["plateFoundByCoPilots"] == true)
    }

    @Test func isEnabledMapsEligibilityKinds() {
        var prefs = UserRepository.NotificationPrefs.default
        prefs.tripInvite = false
        prefs.friend = false
        prefs.family = false
        prefs.inactiveTripReminder = false
        prefs.returnStreakReminder = false
        #expect(prefs.isEnabled(for: .tripInvite) == false)
        #expect(prefs.isEnabled(for: .friendInvite) == false)
        #expect(prefs.isEnabled(for: .familyInvite) == false)
        #expect(prefs.isEnabled(for: .inactiveActiveTripReminder) == false)
        #expect(prefs.isEnabled(for: .returnStreakReminder) == false)
        #expect(prefs.isEnabled(for: .milestone) == true)
    }
}
