//
//  EffectiveSettingsResolver.swift
//  LicensePlateApp
//
//  Effective voice/location settings = privacy kill AND participant prefs.
//
//  There is deliberately no override channel here. Nothing — challenge, event, or host — may
//  turn location on over the user's own choice; every location flag is an AND of the app-level
//  privacy switch and the participant's per-trip pref (COPPA remediation F-4 / FR-45).
//

import Foundation
import Combine

struct EffectiveLocationSettings: Equatable, Sendable {
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrips: Bool
    var skipVoiceConfirmation: Bool
}

@MainActor
protocol EffectiveSettingsProviding: AnyObject {
    func resolve(sessionId: UUID, userId: String) -> EffectiveLocationSettings
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

    /// Every location flag is an AND: the app-level privacy switch and the participant's
    /// per-trip pref must both be on. Off always wins, and no caller can override it.
    func resolve(sessionId: UUID, userId: String) -> EffectiveLocationSettings {
        let privacySave = privacyDefaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        let privacyShow = privacyDefaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
        let privacyTrack = privacyDefaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        let prefs = prefsStore.prefs(sessionId: sessionId, userId: userId)

        let save = privacySave && prefs.saveLocationWhenMarkingPlates
        let show = privacyShow && prefs.showMyLocationOnLargeMap
        let track = privacyTrack && prefs.trackMyLocationDuringTrip

        return EffectiveLocationSettings(
            saveLocationWhenMarkingPlates: save,
            showMyLocationOnLargeMap: show,
            trackMyLocationDuringTrips: track,
            skipVoiceConfirmation: prefs.skipVoiceConfirmation
        )
    }
}
