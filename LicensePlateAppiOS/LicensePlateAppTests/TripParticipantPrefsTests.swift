//
//  TripParticipantPrefsTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripParticipantPrefsTests {

    @Test func fromFirestoreMap_usesDefaultsForMissingKeys() {
        let prefs = TripParticipantPrefs.fromFirestoreMap(["skipVoiceConfirmation": true])
        #expect(prefs.skipVoiceConfirmation == true)
        #expect(prefs.saveLocationWhenMarkingPlates == true)
        #expect(prefs.showMyLocationOnLargeMap == true)
        #expect(prefs.trackMyLocationDuringTrip == true)
        #expect(prefs.source == .seededFromAccountDefaults)
    }

    @Test func fromFirestoreMap_parsesUserEditSource() {
        let prefs = TripParticipantPrefs.fromFirestoreMap([
            "skipVoiceConfirmation": false,
            "saveLocationWhenMarkingPlates": false,
            "showMyLocationOnLargeMap": false,
            "trackMyLocationDuringTrip": false,
            "source": "user_edit"
        ])
        #expect(prefs.source == .userEdit)
        #expect(prefs.saveLocationWhenMarkingPlates == false)
    }

    @Test func participationDefaults_asParticipantPrefs() {
        let defaults = ParticipationDefaults(
            skipVoiceConfirmation: true,
            saveLocationWhenMarkingPlates: false,
            showMyLocationOnLargeMap: true,
            trackMyLocationDuringTrip: false
        )
        let prefs = defaults.asParticipantPrefs()
        #expect(prefs.skipVoiceConfirmation == true)
        #expect(prefs.saveLocationWhenMarkingPlates == false)
        #expect(prefs.source == .seededFromAccountDefaults)
    }
}

@MainActor
struct TripParticipantPrefsStoreTests {

    @Test func applyAndRead_roundTripsThroughUserDefaults() {
        let name = "test.ParticipantPrefsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = TripParticipantPrefsStore(defaults: defaults)
        let sessionId = UUID()
        let prefs = TripParticipantPrefs(
            skipVoiceConfirmation: true,
            saveLocationWhenMarkingPlates: false,
            showMyLocationOnLargeMap: true,
            trackMyLocationDuringTrip: false,
            source: .userEdit
        )
        store.apply(sessionId: sessionId, userId: "u1", prefs: prefs)
        #expect(store.prefs(sessionId: sessionId, userId: "u1") == prefs)
        #expect(store.prefs(sessionId: sessionId, userId: "u2") == .default)
    }

    @Test func tripSettingsToggleDoesNotChangeAccountDefaultKeys() {
        let suite = "test.isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        NewTripDefaultsBootstrap.registerFactoryDefaults(using: defaults)
        defaults.set(false, forKey: NewTripDefaultsKeys.skipVoiceConfirmation)
        defaults.set(true, forKey: NewTripDefaultsKeys.saveLocationWhenMarkingPlates)

        let store = TripParticipantPrefsStore(defaults: defaults)
        let sessionId = UUID()
        store.apply(
            sessionId: sessionId,
            userId: "u1",
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: true,
                saveLocationWhenMarkingPlates: false,
                showMyLocationOnLargeMap: false,
                trackMyLocationDuringTrip: false,
                source: .userEdit
            )
        )

        #expect(defaults.bool(forKey: NewTripDefaultsKeys.skipVoiceConfirmation) == false)
        #expect(defaults.bool(forKey: NewTripDefaultsKeys.saveLocationWhenMarkingPlates) == true)
    }
}
