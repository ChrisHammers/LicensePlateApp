//
//  EffectiveSettingsResolverTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct EffectiveSettingsResolverTests {

    private func makePrivacyDefaults(save: Bool = true, show: Bool = true, track: Bool = true) -> UserDefaults {
        let name = "test.EffectiveResolver.privacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        LocationSettingsBootstrap.registerFactoryDefaults(using: defaults)
        defaults.set(save, forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        defaults.set(show, forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
        defaults.set(track, forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        return defaults
    }

    private func makePrefsStore() -> TripParticipantPrefsStore {
        let name = "test.EffectiveResolver.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return TripParticipantPrefsStore(defaults: defaults)
    }

    @Test func privacyKillOffWinsEvenWhenParticipantOn() {
        let sessionId = UUID()
        let prefsStore = makePrefsStore()
        prefsStore.apply(
            sessionId: sessionId,
            userId: "a",
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: false,
                saveLocationWhenMarkingPlates: true,
                showMyLocationOnLargeMap: true,
                trackMyLocationDuringTrip: true,
                source: .userEdit
            )
        )
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(save: false, show: false, track: false),
            prefsStore: prefsStore
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "a")
        #expect(effective.saveLocationWhenMarkingPlates == false)
        #expect(effective.showMyLocationOnLargeMap == false)
        #expect(effective.trackMyLocationDuringTrips == false)
    }

    @Test func participantOffWinsEvenWhenPrivacyOn() {
        let sessionId = UUID()
        let prefsStore = makePrefsStore()
        prefsStore.apply(
            sessionId: sessionId,
            userId: "a",
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: true,
                saveLocationWhenMarkingPlates: false,
                showMyLocationOnLargeMap: false,
                trackMyLocationDuringTrip: false,
                source: .userEdit
            )
        )
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(),
            prefsStore: prefsStore
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "a")
        #expect(effective.saveLocationWhenMarkingPlates == false)
        #expect(effective.showMyLocationOnLargeMap == false)
        #expect(effective.trackMyLocationDuringTrips == false)
        #expect(effective.skipVoiceConfirmation == true)
    }

    /// COPPA F-4 / FR-45: the resolver has no override channel. A participant who turned
    /// location off stays off no matter what else is on, and resolving never mutates prefs.
    @Test func participantOptOutIsNotOverridableAndResolveDoesNotMutatePrefs() {
        let sessionId = UUID()
        let prefsStore = makePrefsStore()
        let stored = TripParticipantPrefs(
            skipVoiceConfirmation: false,
            saveLocationWhenMarkingPlates: false,
            showMyLocationOnLargeMap: true,
            trackMyLocationDuringTrip: false,
            source: .userEdit
        )
        prefsStore.apply(sessionId: sessionId, userId: "a", prefs: stored)
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(save: true, show: true, track: true),
            prefsStore: prefsStore
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "a")
        #expect(effective.saveLocationWhenMarkingPlates == false)
        #expect(effective.trackMyLocationDuringTrips == false)
        // The one flag the participant left on still resolves on — off-wins is not off-always.
        #expect(effective.showMyLocationOnLargeMap == true)
        #expect(prefsStore.prefs(sessionId: sessionId, userId: "a") == stored)
    }

    @Test func twoParticipantsResolveIndependently() {
        let sessionId = UUID()
        let prefsStore = makePrefsStore()
        prefsStore.apply(
            sessionId: sessionId,
            userId: "a",
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: true,
                saveLocationWhenMarkingPlates: true,
                showMyLocationOnLargeMap: true,
                trackMyLocationDuringTrip: true,
                source: .userEdit
            )
        )
        prefsStore.apply(
            sessionId: sessionId,
            userId: "b",
            prefs: TripParticipantPrefs(
                skipVoiceConfirmation: false,
                saveLocationWhenMarkingPlates: false,
                showMyLocationOnLargeMap: false,
                trackMyLocationDuringTrip: false,
                source: .userEdit
            )
        )
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(),
            prefsStore: prefsStore
        )
        #expect(resolver.resolve(sessionId: sessionId, userId: "a").skipVoiceConfirmation == true)
        #expect(resolver.resolve(sessionId: sessionId, userId: "b").skipVoiceConfirmation == false)
        #expect(resolver.resolve(sessionId: sessionId, userId: "a").saveLocationWhenMarkingPlates == true)
        #expect(resolver.resolve(sessionId: sessionId, userId: "b").saveLocationWhenMarkingPlates == false)
    }

    @Test func missingPrefsUsesFactoryDefaults() {
        let sessionId = UUID()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(),
            prefsStore: makePrefsStore()
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "ghost")
        #expect(effective.saveLocationWhenMarkingPlates == true)
        #expect(effective.skipVoiceConfirmation == false)
    }
}
