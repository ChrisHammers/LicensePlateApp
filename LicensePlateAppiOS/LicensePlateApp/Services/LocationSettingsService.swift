//
//  LocationSettingsService.swift
//  LicensePlateApp
//
//  GPS Step 1 — Single source of truth for effective location settings.
//

import Foundation
import Combine

// MARK: - Keys

/// Global (app-wide) location toggle keys, owned by the Privacy & Permissions screen.
/// Distinct from `NewTripDefaultsKeys` ("default*" prefix), which hold the per-trip values.
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

/// Read-only effective location settings. Consumers (map, discovery, route tracking)
/// ask this — never the raw UserDefaults keys — whether a location behavior is enabled.
protocol LocationSettingsProviding: AnyObject {
    var saveLocationWhenMarkingPlates: Bool { get }
    var showMyLocationOnLargeMap: Bool { get }
    var trackMyLocationDuringTrips: Bool { get }
}

/// Effective value = global kill switch (`LocationSettingsKeys`, Privacy & Permissions)
/// AND per-trip value (`NewTripDefaultsKeys` "default*" keys, edited in trip setup,
/// New Trip Defaults, and GameSettingsView). Turning either side off disables the behavior.
///
/// The per-trip side is not yet persisted on TripSession; the "default*" keys double as the
/// current-trip value because GameSettingsView live-writes them mid-trip. Revisit when
/// route tracking gives trips a persisted location config.
///
/// Privacy: this type deals only in booleans. It must never read, hold, or log coordinates,
/// and no location-derived value may reach AnalyticsService from here.
/// ObservableObject so views re-evaluate effective flags live when a toggle changes
/// (Privacy & Permissions and Game Settings both write through @AppStorage → UserDefaults).
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
            && defaults.bool(forKey: NewTripDefaultsKeys.saveLocationWhenMarkingPlates)
    }

    var showMyLocationOnLargeMap: Bool {
        defaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
            && defaults.bool(forKey: NewTripDefaultsKeys.showMyLocationOnLargeMap)
    }

    var trackMyLocationDuringTrips: Bool {
        defaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
            && defaults.bool(forKey: NewTripDefaultsKeys.trackMyLocationDuringTrip)
    }
}
