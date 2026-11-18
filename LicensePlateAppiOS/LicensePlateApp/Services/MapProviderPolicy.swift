//
//  MapProviderPolicy.swift
//  LicensePlateApp
//
//  COPPA F-37 (FR-81(e), OD-6 keep-and-gate, owner 2026-11-17): Google Maps is linked
//  but never started at launch. It is reachable only in a DEBUG build, with the
//  DEBUG-only Map Provider switch set to Google, in a confirmed-adult session — and
//  only then is the SDK given its key, just before the first Google map is created.
//

import Foundation

/// Resolves which map provider a map view actually shows.
enum MapProviderPolicy {
    /// Compile-time build flag the live resolver passes in. A release build is `false`,
    /// so a stale stored "Google" value can never reach the Google path.
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Pure policy. Google only when ALL hold: DEBUG build, the stored switch says
    /// Google, and the session is `.confirmedNonChild` (strict FR-19 trust, as ads and
    /// purchases use — not the OD-8 location relaxation). Child, ratcheted-anonymous and
    /// unresolved sessions stay on Apple whatever the stored switch says.
    static func effectiveProvider(
        storedRaw: String?,
        posture: ChildSessionPosture,
        isDebugBuild: Bool
    ) -> AppMapProvider {
        guard isDebugBuild,
              posture == .confirmedNonChild,
              let storedRaw,
              AppMapProvider(rawValue: storedRaw) == .google
        else { return AppPreferences.defaultMapProvider() }
        return .google
    }

    /// What the map views ask. Starts the Google Maps SDK (once) only when the pure
    /// policy picks Google; falls back to Apple when the SDK cannot start (no usable
    /// key configured). `start` is injectable for tests only; the views use the default.
    static func resolvedProvider(
        storedRaw: String?,
        posture: ChildSessionPosture,
        start: () -> Bool = { GoogleMapsService.shared.startIfNeeded() }
    ) -> AppMapProvider {
        let provider = effectiveProvider(storedRaw: storedRaw, posture: posture, isDebugBuild: isDebugBuild)
        guard provider == .google, start() else {
            return AppPreferences.defaultMapProvider()
        }
        return .google
    }
}
