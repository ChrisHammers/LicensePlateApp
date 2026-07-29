//
//  EffectiveSettingsResolver.swift
//  LicensePlateApp
//
//  Effective voice/location settings = privacy kill AND participant prefs (+ future challenge overrides).
//

import Foundation
import Combine

/// Optional future challenge/event overrides. Defaults leave participant choice intact.
struct ChallengeSettingsOverrides: Equatable, Sendable {
    var requiresLocation: Bool
    var requiresTracking: Bool

    static let none = ChallengeSettingsOverrides(requiresLocation: false, requiresTracking: false)
}

struct EffectiveLocationSettings: Equatable, Sendable {
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrips: Bool
    var skipVoiceConfirmation: Bool
}

@MainActor
protocol EffectiveSettingsProviding: AnyObject {
    func resolve(
        sessionId: UUID,
        userId: String,
        challenge: ChallengeSettingsOverrides
    ) -> EffectiveLocationSettings
}

/// Resolves effective settings for the viewer on a trip without mutating stored prefs.
@MainActor
final class EffectiveSettingsResolver: EffectiveSettingsProviding, ObservableObject {
    static let shared = EffectiveSettingsResolver()

    private let privacyDefaults: UserDefaults
    private let prefsStore: TripParticipantPrefsStore
    private var cancellables = Set<AnyCancellable>()

    init(
        privacyDefaults: UserDefaults = .standard,
        prefsStore: TripParticipantPrefsStore = .shared
    ) {
        self.privacyDefaults = privacyDefaults
        self.prefsStore = prefsStore
        prefsStore.$revision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: privacyDefaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func resolve(
        sessionId: UUID,
        userId: String,
        challenge: ChallengeSettingsOverrides = .none
    ) -> EffectiveLocationSettings {
        let privacySave = privacyDefaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        let privacyShow = privacyDefaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
        let privacyTrack = privacyDefaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        let prefs = prefsStore.prefs(sessionId: sessionId, userId: userId)

        let save = challenge.requiresLocation
            || (privacySave && prefs.saveLocationWhenMarkingPlates)
        let show = privacyShow && prefs.showMyLocationOnLargeMap
        let track = challenge.requiresTracking
            || (privacyTrack && prefs.trackMyLocationDuringTrip)

        return EffectiveLocationSettings(
            saveLocationWhenMarkingPlates: save,
            showMyLocationOnLargeMap: show,
            trackMyLocationDuringTrips: track,
            skipVoiceConfirmation: prefs.skipVoiceConfirmation
        )
    }
}
