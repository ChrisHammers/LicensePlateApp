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
    private var reapplyCancellable: AnyCancellable?

    /// COPPA F-7 (FR-33 amended): while true, ALL THREE flags read false and any
    /// stored true value is rewritten to false — including on later flag flips (the
    /// didChange re-apply below). Set only by `ChildSessionPostureCoordinator` at the
    /// FR-23 seam; adult sessions are never forced (owner decision D-11).
    ///
    /// COPPA F-31 (FR-75): this is the DURABLE half of the kill switch, and it is fed by
    /// the narrow `ChildSessionPosture.rewritesStoredLocationFlagsOff` (a real child
    /// signal) precisely because the rewrite destroys the value it overwrites. It is no
    /// longer the enforcement layer: `EffectiveSettingsResolver` ANDs the child signal in
    /// directly, so a restricted session is denied location whether or not this ever ran.
    private(set) var isChildSessionForcedOff = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // FR-33 re-apply, synchronous on the writing thread: a flag flipped back on
        // under a child session is forced off again immediately at the single source
        // of truth (self-terminating: only true values are rewritten).
        reapplyCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .sink { [weak self] _ in
                self?.forceStoredFlagsOffIfNeeded()
            }
        defaultsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func setChildSessionForcedOff(_ forced: Bool) {
        guard isChildSessionForcedOff != forced else { return }
        isChildSessionForcedOff = forced
        forceStoredFlagsOffIfNeeded()
        objectWillChange.send()
    }

    /// Writes false only for keys currently true (also prevents didChange loops).
    private func forceStoredFlagsOffIfNeeded() {
        guard isChildSessionForcedOff else { return }
        for key in [
            LocationSettingsKeys.saveLocationWhenMarkingPlates,
            LocationSettingsKeys.showMyLocationOnLargeMap,
            LocationSettingsKeys.trackMyLocationDuringTrips
        ] where defaults.bool(forKey: key) {
            defaults.set(false, forKey: key)
        }
    }

    var saveLocationWhenMarkingPlates: Bool {
        !isChildSessionForcedOff && defaults.bool(forKey: LocationSettingsKeys.saveLocationWhenMarkingPlates)
    }

    var showMyLocationOnLargeMap: Bool {
        !isChildSessionForcedOff && defaults.bool(forKey: LocationSettingsKeys.showMyLocationOnLargeMap)
    }

    var trackMyLocationDuringTrips: Bool {
        !isChildSessionForcedOff && defaults.bool(forKey: LocationSettingsKeys.trackMyLocationDuringTrips)
    }
}
