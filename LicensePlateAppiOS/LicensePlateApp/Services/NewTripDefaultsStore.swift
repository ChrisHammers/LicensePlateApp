//
//  NewTripDefaultsStore.swift
//  LicensePlateApp
//
//  UserDefaults keys and persistence for "New Trip/Game Defaults" settings.
//

import Foundation

// MARK: - Keys

enum NewTripDefaultsKeys {
    static let includeUS = "defaultIncludeUS"
    static let includeCanada = "defaultIncludeCanada"
    static let includeMexico = "defaultIncludeMexico"
    static let startTripRightAway = "defaultStartTripRightAway"
    static let skipVoiceConfirmation = "defaultSkipVoiceConfirmation"
    static let holdToTalk = "defaultHoldToTalk"
    static let saveLocationWhenMarkingPlates = "defaultSaveLocationWhenMarkingPlates"
    static let showMyLocationOnLargeMap = "defaultShowMyLocationOnLargeMap"
    static let trackMyLocationDuringTrip = "defaultTrackMyLocationDuringTrip"
    static let showMyActiveTripOnLargeMap = "defaultShowMyActiveTripOnLargeMap"
    static let showMyActiveTripOnSmallMap = "defaultShowMyActiveTripOnSmallMap"
}

// MARK: - Snapshot

struct NewTripDefaults: Equatable {
    var includeUS: Bool
    var includeCanada: Bool
    var includeMexico: Bool
    var startTripRightAway: Bool
    var skipVoiceConfirmation: Bool
    var holdToTalk: Bool
    var saveLocationWhenMarkingPlates: Bool
    var showMyLocationOnLargeMap: Bool
    var trackMyLocationDuringTrip: Bool
    var showMyActiveTripOnLargeMap: Bool
    var showMyActiveTripOnSmallMap: Bool

    /// Country + territory scope implied by Game Defaults (Settings → Game Defaults).
    var gameDefaultScopeOptions: GameDefaultScopeOptions {
        GameDefaultScopeOptions(
            includeUS: includeUS,
            includeCanada: includeCanada,
            includeMexico: includeMexico,
            includeUSTerritories: includeUS,
            includeDC: includeUS,
            includeCanadianTerritories: includeCanada
        )
    }
}

/// License plate scope toggles shown under Game Options in setup; comparable to Settings → Game Defaults.
struct GameDefaultScopeOptions: Equatable, Sendable {
    var includeUS: Bool
    var includeCanada: Bool
    var includeMexico: Bool
    var includeUSTerritories: Bool
    var includeDC: Bool
    var includeCanadianTerritories: Bool
}

// MARK: - Factory registration

enum NewTripDefaultsBootstrap {
    /// Values used with `UserDefaults.register(defaults:)` so first-read behavior matches product defaults without persisting until the user changes a setting.
    static var factoryRegistration: [String: Any] {
        [
            NewTripDefaultsKeys.includeUS: true,
            NewTripDefaultsKeys.includeCanada: true,
            NewTripDefaultsKeys.includeMexico: true,
            NewTripDefaultsKeys.startTripRightAway: true,
            NewTripDefaultsKeys.skipVoiceConfirmation: false,
            NewTripDefaultsKeys.holdToTalk: true,
            NewTripDefaultsKeys.saveLocationWhenMarkingPlates: true,
            NewTripDefaultsKeys.showMyLocationOnLargeMap: true,
            NewTripDefaultsKeys.trackMyLocationDuringTrip: true,
            NewTripDefaultsKeys.showMyActiveTripOnLargeMap: true,
            NewTripDefaultsKeys.showMyActiveTripOnSmallMap: true,
        ]
    }

    static func registerFactoryDefaults(using defaults: UserDefaults = .standard) {
        defaults.register(defaults: factoryRegistration)
    }
}

// MARK: - Storing

protocol NewTripDefaultsStoring: AnyObject {
    func load() -> NewTripDefaults
    func save(_ snapshot: NewTripDefaults)
}

final class UserDefaultsNewTripDefaultsStore: NewTripDefaultsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NewTripDefaults {
        NewTripDefaults(
            includeUS: defaults.bool(forKey: NewTripDefaultsKeys.includeUS),
            includeCanada: defaults.bool(forKey: NewTripDefaultsKeys.includeCanada),
            includeMexico: defaults.bool(forKey: NewTripDefaultsKeys.includeMexico),
            startTripRightAway: defaults.bool(forKey: NewTripDefaultsKeys.startTripRightAway),
            skipVoiceConfirmation: defaults.bool(forKey: NewTripDefaultsKeys.skipVoiceConfirmation),
            holdToTalk: defaults.bool(forKey: NewTripDefaultsKeys.holdToTalk),
            saveLocationWhenMarkingPlates: defaults.bool(forKey: NewTripDefaultsKeys.saveLocationWhenMarkingPlates),
            showMyLocationOnLargeMap: defaults.bool(forKey: NewTripDefaultsKeys.showMyLocationOnLargeMap),
            trackMyLocationDuringTrip: defaults.bool(forKey: NewTripDefaultsKeys.trackMyLocationDuringTrip),
            showMyActiveTripOnLargeMap: defaults.bool(forKey: NewTripDefaultsKeys.showMyActiveTripOnLargeMap),
            showMyActiveTripOnSmallMap: defaults.bool(forKey: NewTripDefaultsKeys.showMyActiveTripOnSmallMap)
        )
    }

    func save(_ snapshot: NewTripDefaults) {
        defaults.set(snapshot.includeUS, forKey: NewTripDefaultsKeys.includeUS)
        defaults.set(snapshot.includeCanada, forKey: NewTripDefaultsKeys.includeCanada)
        defaults.set(snapshot.includeMexico, forKey: NewTripDefaultsKeys.includeMexico)
        defaults.set(snapshot.startTripRightAway, forKey: NewTripDefaultsKeys.startTripRightAway)
        defaults.set(snapshot.skipVoiceConfirmation, forKey: NewTripDefaultsKeys.skipVoiceConfirmation)
        defaults.set(snapshot.holdToTalk, forKey: NewTripDefaultsKeys.holdToTalk)
        defaults.set(snapshot.saveLocationWhenMarkingPlates, forKey: NewTripDefaultsKeys.saveLocationWhenMarkingPlates)
        defaults.set(snapshot.showMyLocationOnLargeMap, forKey: NewTripDefaultsKeys.showMyLocationOnLargeMap)
        defaults.set(snapshot.trackMyLocationDuringTrip, forKey: NewTripDefaultsKeys.trackMyLocationDuringTrip)
        defaults.set(snapshot.showMyActiveTripOnLargeMap, forKey: NewTripDefaultsKeys.showMyActiveTripOnLargeMap)
        defaults.set(snapshot.showMyActiveTripOnSmallMap, forKey: NewTripDefaultsKeys.showMyActiveTripOnSmallMap)
    }
}
