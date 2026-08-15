//
//  EffectiveSettingsResolver.swift
//  LicensePlateApp
//
//  Effective voice/location settings = child signal AND privacy kill AND participant prefs.
//
//  There is deliberately no override channel here. Nothing — challenge, event, or host — may
//  turn location on over the user's own choice; every location flag is an AND of the app-level
//  privacy switch and the participant's per-trip pref (COPPA remediation F-4 / FR-45),
//  with the child-restriction signal ANDed in ahead of both (COPPA F-31 / FR-75a).
//

import Foundation
import Combine

struct EffectiveLocationSettings: Equatable, Sendable {
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrips: Bool
    var skipVoiceConfirmation: Bool
}

/// COPPA F-31 (FR-75a): the child-restriction signal, handed to the resolver as a DIRECT
/// input rather than inferred from a persisted side effect.
///
/// Before F-31 the resolver read raw `UserDefaults`, so a child session was only actually
/// denied location once `ChildSessionPostureCoordinator` had rewritten three keys through
/// `LocationSettingsService.setChildSessionForcedOff`. That write still happens (belt and
/// braces, and it makes a child's stored preferences durable), but enforcement no longer
/// depends on it having landed first.
@MainActor
struct ChildLocationRestrictionSignal {
    /// True while this session may not use ANY location capability.
    var isRestricted: () -> Bool
    /// Fires when the answer may have changed, so effective settings re-publish even when
    /// no stored flag was rewritten — e.g. a launch-time `.unresolved` session resolving
    /// to a confirmed adult while a trip is already active.
    var changes: AnyPublisher<Void, Never>

    /// The single source of truth: the same projection the FR-33 OS-prompt gate
    /// (`LocationManager.childLocationRestrictionProvider`) reads.
    static var live: ChildLocationRestrictionSignal {
        let coordinator = ChildSessionPostureCoordinator.shared
        return ChildLocationRestrictionSignal(
            isRestricted: { coordinator.isLocationRestrictedForCurrentFlow },
            changes: coordinator.objectWillChange.eraseToAnyPublisher()
        )
    }

    /// Test seam: a constant answer that never changes.
    static func fixed(_ restricted: Bool) -> ChildLocationRestrictionSignal {
        ChildLocationRestrictionSignal(
            isRestricted: { restricted },
            changes: Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
        )
    }
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
    private let childRestriction: ChildLocationRestrictionSignal
    private var cancellables = Set<AnyCancellable>()

    /// `childRestriction` defaults to `.live` (resolved in the body, not as a default
    /// argument — `.live` is main-actor isolated); tests inject `.fixed(_:)`.
    init(
        privacyDefaults: UserDefaults = .standard,
        prefsStore: TripParticipantPrefsStore = .shared,
        childRestriction: ChildLocationRestrictionSignal? = nil
    ) {
        let childRestriction = childRestriction ?? .live
        self.privacyDefaults = privacyDefaults
        self.prefsStore = prefsStore
        self.childRestriction = childRestriction
        childRestriction.changes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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

    /// Every location flag is an AND: the child-restriction signal must be clear, and the
    /// app-level privacy switch and the participant's per-trip pref must both be on. Off
    /// always wins, and no caller can override it.
    ///
    /// COPPA F-31 (FR-75a): the child signal is ANDed HERE, as a direct input, so a
    /// restricted session resolves every location capability off even when the stored
    /// privacy flags are still at their factory-default `true` — the first-launch window
    /// where the async posture routine had not run yet. The AND can only ever turn a
    /// capability OFF: an adult's stored preferences round-trip through untouched, and
    /// nothing here can turn a capability on that the user turned off.
    ///
    /// `skipVoiceConfirmation` is not a location capability and is deliberately outside
    /// the child AND.
    func resolve(sessionId: UUID, userId: String) -> EffectiveLocationSettings {
        let childRestricted = childRestriction.isRestricted()
        let privacySave = privacyDefaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
        let privacyShow = privacyDefaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
        let privacyTrack = privacyDefaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
        let prefs = prefsStore.prefs(sessionId: sessionId, userId: userId)

        let save = !childRestricted && privacySave && prefs.saveLocationWhenMarkingPlates
        let show = !childRestricted && privacyShow && prefs.showMyLocationOnLargeMap
        let track = !childRestricted && privacyTrack && prefs.trackMyLocationDuringTrip

        return EffectiveLocationSettings(
            saveLocationWhenMarkingPlates: save,
            showMyLocationOnLargeMap: show,
            trackMyLocationDuringTrips: track,
            skipVoiceConfirmation: prefs.skipVoiceConfirmation
        )
    }
}
