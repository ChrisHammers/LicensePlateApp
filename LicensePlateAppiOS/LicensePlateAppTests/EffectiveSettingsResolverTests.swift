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
            prefsStore: prefsStore,
            childRestriction: .fixed(false)
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
            prefsStore: prefsStore,
            childRestriction: .fixed(false)
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
            prefsStore: prefsStore,
            childRestriction: .fixed(false)
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
            prefsStore: prefsStore,
            childRestriction: .fixed(false)
        )
        #expect(resolver.resolve(sessionId: sessionId, userId: "a").skipVoiceConfirmation == true)
        #expect(resolver.resolve(sessionId: sessionId, userId: "b").skipVoiceConfirmation == false)
        #expect(resolver.resolve(sessionId: sessionId, userId: "a").saveLocationWhenMarkingPlates == true)
        #expect(resolver.resolve(sessionId: sessionId, userId: "b").saveLocationWhenMarkingPlates == false)
    }

    // MARK: - COPPA F-31 (FR-75a): the child signal is a direct input, ANDed here

    /// The full matrix: child signal × stored privacy flags × participant prefs. A
    /// restricted session resolves all three location capabilities off in EVERY cell,
    /// including the dangerous one the pre-F-31 resolver got wrong — factory-default
    /// `true` flags on a device where the persisted kill switch has not been written yet.
    @Test func childRestrictedResolvesLocationOffAcrossEveryStoredCombination() {
        let sessionId = UUID()
        for privacyOn in [true, false] {
            for prefsOn in [true, false] {
                let prefsStore = makePrefsStore()
                prefsStore.apply(
                    sessionId: sessionId,
                    userId: "a",
                    prefs: TripParticipantPrefs(
                        skipVoiceConfirmation: true,
                        saveLocationWhenMarkingPlates: prefsOn,
                        showMyLocationOnLargeMap: prefsOn,
                        trackMyLocationDuringTrip: prefsOn,
                        source: .userEdit
                    )
                )
                let resolver = EffectiveSettingsResolver(
                    privacyDefaults: makePrivacyDefaults(save: privacyOn, show: privacyOn, track: privacyOn),
                    prefsStore: prefsStore,
                    childRestriction: .fixed(true)
                )
                let effective = resolver.resolve(sessionId: sessionId, userId: "a")
                let cell = "privacy=\(privacyOn) prefs=\(prefsOn)"
                #expect(effective.saveLocationWhenMarkingPlates == false, "save leaked: \(cell)")
                #expect(effective.showMyLocationOnLargeMap == false, "show leaked: \(cell)")
                #expect(effective.trackMyLocationDuringTrips == false, "track leaked: \(cell)")
                // Voice confirmation is not a location capability: the child AND must
                // not silently change it.
                #expect(effective.skipVoiceConfirmation == true, "voice pref altered: \(cell)")
            }
        }
    }

    /// The unrestricted half of the same matrix: with the child signal clear, every cell
    /// is exactly `privacy AND pref` — F-31 adds a term, it does not redefine the others.
    @Test func unrestrictedSessionResolvesPrivacyAndPrefsUnchanged() {
        let sessionId = UUID()
        for privacyOn in [true, false] {
            for prefsOn in [true, false] {
                let prefsStore = makePrefsStore()
                prefsStore.apply(
                    sessionId: sessionId,
                    userId: "a",
                    prefs: TripParticipantPrefs(
                        skipVoiceConfirmation: false,
                        saveLocationWhenMarkingPlates: prefsOn,
                        showMyLocationOnLargeMap: prefsOn,
                        trackMyLocationDuringTrip: prefsOn,
                        source: .userEdit
                    )
                )
                let resolver = EffectiveSettingsResolver(
                    privacyDefaults: makePrivacyDefaults(save: privacyOn, show: privacyOn, track: privacyOn),
                    prefsStore: prefsStore,
                    childRestriction: .fixed(false)
                )
                let effective = resolver.resolve(sessionId: sessionId, userId: "a")
                let expected = privacyOn && prefsOn
                let cell = "privacy=\(privacyOn) prefs=\(prefsOn)"
                #expect(effective.saveLocationWhenMarkingPlates == expected, "save drifted: \(cell)")
                #expect(effective.showMyLocationOnLargeMap == expected, "show drifted: \(cell)")
                #expect(effective.trackMyLocationDuringTrips == expected, "track drifted: \(cell)")
            }
        }
    }

    /// FR-75(a) is an AND, never an OR: the child signal can only turn capabilities OFF.
    /// An adult keeps their own choices, and a restricted session's stored preferences
    /// survive the restriction so they come back intact when it lifts.
    @Test func childRestrictionNeverForcesOnAndNeverMutatesStoredState() {
        let sessionId = UUID()
        let prefsStore = makePrefsStore()
        let stored = TripParticipantPrefs(
            skipVoiceConfirmation: false,
            saveLocationWhenMarkingPlates: true,
            showMyLocationOnLargeMap: false,
            trackMyLocationDuringTrip: true,
            source: .userEdit
        )
        prefsStore.apply(sessionId: sessionId, userId: "a", prefs: stored)
        let privacy = makePrivacyDefaults(save: true, show: true, track: true)

        let restricted = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: prefsStore,
            childRestriction: .fixed(true)
        )
        let held = restricted.resolve(sessionId: sessionId, userId: "a")
        #expect(held.saveLocationWhenMarkingPlates == false)
        #expect(held.trackMyLocationDuringTrips == false)

        // Nothing was written: same defaults object, same prefs row.
        #expect(privacy.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates) == true)
        #expect(privacy.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips) == true)
        #expect(prefsStore.prefs(sessionId: sessionId, userId: "a") == stored)

        // Same stored state, restriction lifted: the user's own choices, unchanged —
        // including the one they had turned off, which nothing may turn back on.
        let unrestricted = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: prefsStore,
            childRestriction: .fixed(false)
        )
        let restored = unrestricted.resolve(sessionId: sessionId, userId: "a")
        #expect(restored.saveLocationWhenMarkingPlates == true)
        #expect(restored.trackMyLocationDuringTrips == true)
        #expect(restored.showMyLocationOnLargeMap == false)
    }

    /// The literal defect: factory defaults registered, no explicit writes, no persisted
    /// kill switch — the state a first launch is in before any posture routine has run.
    @Test func factoryDefaultsWithChildSignalResolveOffWithoutAnyPersistedKillSwitch() {
        let sessionId = UUID()
        let name = "test.EffectiveResolver.factory.\(UUID().uuidString)"
        let privacy = UserDefaults(suiteName: name)!
        privacy.removePersistentDomain(forName: name)
        LocationSettingsBootstrap.registerFactoryDefaults(using: privacy)
        // Factory defaults are all true — the value the old resolver read straight through.
        #expect(privacy.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips) == true)

        let resolver = EffectiveSettingsResolver(
            privacyDefaults: privacy,
            prefsStore: makePrefsStore(),
            childRestriction: .fixed(true)
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "ghost")
        #expect(effective.saveLocationWhenMarkingPlates == false)
        #expect(effective.showMyLocationOnLargeMap == false)
        #expect(effective.trackMyLocationDuringTrips == false)
    }

    @Test func missingPrefsUsesFactoryDefaults() {
        let sessionId = UUID()
        let resolver = EffectiveSettingsResolver(
            privacyDefaults: makePrivacyDefaults(),
            prefsStore: makePrefsStore(),
            childRestriction: .fixed(false)
        )
        let effective = resolver.resolve(sessionId: sessionId, userId: "ghost")
        #expect(effective.saveLocationWhenMarkingPlates == true)
        #expect(effective.skipVoiceConfirmation == false)
    }
}
