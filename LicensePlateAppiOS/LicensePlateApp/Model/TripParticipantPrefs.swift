//
//  TripParticipantPrefs.swift
//  LicensePlateApp
//
//  Per-participant voice/location prefs for a trip session (not shared game rules).
//

import Foundation

enum TripParticipantPrefsSource: String, Codable, Sendable {
    case seededFromAccountDefaults = "seeded_from_account_defaults"
    case userEdit = "user_edit"
}

/// Snapshot of personal prefs for one user on one trip.
struct TripParticipantPrefs: Equatable, Sendable {
    var skipVoiceConfirmation: Bool
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrip: Bool
    var source: TripParticipantPrefsSource

    static let `default` = TripParticipantPrefs(
        skipVoiceConfirmation: false,
        saveLocationWhenMarkingPlates: true,
        showMyLocationOnLargeMap: true,
        trackMyLocationDuringTrip: true,
        source: .seededFromAccountDefaults
    )

    static func fromFirestoreMap(_ raw: [String: Any]?) -> TripParticipantPrefs {
        let d = TripParticipantPrefs.default
        guard let raw else { return d }
        let sourceRaw = raw["source"] as? String
        let source = TripParticipantPrefsSource(rawValue: sourceRaw ?? "") ?? .seededFromAccountDefaults
        return TripParticipantPrefs(
            skipVoiceConfirmation: (raw["skipVoiceConfirmation"] as? Bool) ?? d.skipVoiceConfirmation,
            saveLocationWhenMarkingPlates: (raw["saveLocationWhenMarkingPlates"] as? Bool) ?? d.saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: (raw["showMyLocationOnLargeMap"] as? Bool) ?? d.showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: (raw["trackMyLocationDuringTrip"] as? Bool) ?? d.trackMyLocationDuringTrip,
            source: source
        )
    }

    /// Full boolean map for callable upsert (no source — server sets user_edit).
    var callablePrefsMap: [String: Bool] {
        [
            "skipVoiceConfirmation": skipVoiceConfirmation,
            "saveLocationWhenMarkingPlates": saveLocationWhenMarkingPlates,
            "showMyLocationOnLargeMap": showMyLocationOnLargeMap,
            "trackMyLocationDuringTrip": trackMyLocationDuringTrip
        ]
    }
}

/// Account-level defaults that seed participant prefs at create/join.
struct ParticipationDefaults: Equatable, Sendable {
    var skipVoiceConfirmation: Bool
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrip: Bool

    static let `default` = ParticipationDefaults(
        skipVoiceConfirmation: false,
        saveLocationWhenMarkingPlates: true,
        showMyLocationOnLargeMap: true,
        trackMyLocationDuringTrip: true
    )

    static func fromFirestoreMap(_ raw: [String: Any]?) -> ParticipationDefaults {
        let d = ParticipationDefaults.default
        guard let raw else { return d }
        return ParticipationDefaults(
            skipVoiceConfirmation: (raw["skipVoiceConfirmation"] as? Bool) ?? d.skipVoiceConfirmation,
            saveLocationWhenMarkingPlates: (raw["saveLocationWhenMarkingPlates"] as? Bool) ?? d.saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: (raw["showMyLocationOnLargeMap"] as? Bool) ?? d.showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: (raw["trackMyLocationDuringTrip"] as? Bool) ?? d.trackMyLocationDuringTrip
        )
    }

    var firestoreMap: [String: Bool] {
        [
            "skipVoiceConfirmation": skipVoiceConfirmation,
            "saveLocationWhenMarkingPlates": saveLocationWhenMarkingPlates,
            "showMyLocationOnLargeMap": showMyLocationOnLargeMap,
            "trackMyLocationDuringTrip": trackMyLocationDuringTrip
        ]
    }

    func asParticipantPrefs(source: TripParticipantPrefsSource = .seededFromAccountDefaults) -> TripParticipantPrefs {
        TripParticipantPrefs(
            skipVoiceConfirmation: skipVoiceConfirmation,
            saveLocationWhenMarkingPlates: saveLocationWhenMarkingPlates,
            showMyLocationOnLargeMap: showMyLocationOnLargeMap,
            trackMyLocationDuringTrip: trackMyLocationDuringTrip,
            source: source
        )
    }
}
