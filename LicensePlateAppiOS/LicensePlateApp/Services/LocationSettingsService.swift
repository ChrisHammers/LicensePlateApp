//
//  LocationSettingsService.swift
//  LicensePlateApp
//
//  GPS Step 1 — Device privacy kill switches (Privacy & Permissions).
//  Trip-scoped personal prefs are resolved via EffectiveSettingsResolver + participant_prefs.
//

import Foundation
import Combine

// MARK: - Keys

/// Global (app-wide) location toggle keys, owned by the Privacy & Permissions screen.
/// Distinct from account `participationDefaults` / per-trip `participant_prefs`.
enum LocationSettingsKeys {
    static let saveLocationWhenMarkingPlates = "saveLocationWhenMarkingPlates"
    static let showMyLocationOnLargeMap = "showMyLocationOnLargeMap"
    static let trackMyLocationDuringTrips = "trackMyLocationDuringTrips"
}

// MARK: - Bootstrap

/// Registers factory defaults (all true) for the global keys so `UserDefaults.bool` readers
/// see the same unset-value semantics as the `@AppStorage(..., default: true)` bindings
/// in PrivacyPermissionsView. `register` never overwrites values the user has set.
enum LocationSettingsBootstrap {
    static func registerFactoryDefaults(using defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            LocationSettingsKeys.saveLocationWhenMarkingPlates: true,
            LocationSettingsKeys.showMyLocationOnLargeMap: true,
            LocationSettingsKeys.trackMyLocationDuringTrips: true
        ])
    }
}

// MARK: - Providing

/// Read-only effective location settings for consumers that do not yet have a trip context.
/// Prefer `EffectiveSettingsResolver` / `SessionBoundLocationSettings` inside an active trip.
protocol LocationSettingsProviding: AnyObject {
    var saveLocationWhenMarkingPlates: Bool { get }
    var showMyLocationOnLargeMap: Bool { get }
    var trackMyLocationDuringTrips: Bool { get }
}

/// Device privacy kill switches only. Trip participation prefs are AND-ed in
/// `EffectiveSettingsResolver`, not here — so editing trip settings cannot mutate account defaults.
///
/// Privacy: this type deals only in booleans. It must never read, hold, or log coordinates,
/// and no location-derived value may reach AnalyticsService from here.
final class LocationSettingsService: LocationSettingsProviding, ObservableObject {

    static let shared = LocationSettingsService()

    private let defaults: UserDefaults
    private var defaultsCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    var saveLocationWhenMarkingPlates: Bool {
        defaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
    }

    var showMyLocationOnLargeMap: Bool {
        defaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
    }

    var trackMyLocationDuringTrips: Bool {
        defaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
    }
}
