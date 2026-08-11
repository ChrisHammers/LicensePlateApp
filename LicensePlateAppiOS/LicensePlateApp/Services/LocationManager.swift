//
//  LocationManager.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import CoreLocation
import Combine

/// App-wide location source (GPS Step 2). One CLLocationManager for all views;
/// later steps (location-at-find, route tracking) read the shared cached fix.
/// When-In-Use only — never auto-prompts for Always.
/// Privacy: coordinates stay in-process; never log them or pass them to AnalyticsService.
@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var location: CLLocation?
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()
    /// True while an authorization prompt we triggered is outstanding, so the delegate
    /// starts updates on grant (keeps the map dot appearing mid-flow) without turning
    /// GPS on every time the singleton observes an already-authorized status.
    /// Internal-read for tests (COPPA FR-33 prompt-gate pin).
    private(set) var didRequestAuthorization = false

    /// COPPA F-7 (FR-33): every location feature is forced off for child sessions, so
    /// the OS location prompt is never triggered for one — from any surface
    /// (onboarding permissions, settings, trip/gameplay onAppear). Injectable for tests.
    var childLocationRestrictionProvider: () -> Bool = {
        ChildSessionPostureCoordinator.shared.isLocationRestrictedForCurrentFlow
    }
    /// Update requests are ref-counted by named holds so route tracking (GPS Step 6)
    /// survives a map's onDisappear stop. Views keep calling the default-"map" methods.
    private var updateHolds: Set<String> = []
    private var oneShotInFlight = false
    private static let mapHold = "map"
    private static let routeTrackingHold = "routeTracking"

    /// Internal (not private) so tests can pin the child prompt gate on a fresh
    /// instance; production code uses `shared`.
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    var isAuthorizedForLocation: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Pure gate (COPPA FR-33): child sessions/flows never see the OS location prompt.
    static func mayRequestAuthorization(isChildLocationRestricted: Bool) -> Bool {
        !isChildLocationRestricted
    }

    /// Request When In Use authorization. No-op for child sessions (FR-33): requesting
    /// a permission every dependent feature is forced off for is never done.
    func requestAuthorization() {
        guard Self.mayRequestAuthorization(isChildLocationRestricted: childLocationRestrictionProvider()) else {
            return
        }
        didRequestAuthorization = true
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation(hold: String = LocationManager.mapHold) {
        guard isAuthorizedForLocation else { return }
        updateHolds.insert(hold)
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation(hold: String = LocationManager.mapHold) {
        updateHolds.remove(hold)
        if updateHolds.isEmpty {
            locationManager.stopUpdatingLocation()
        }
    }

    /// One-shot fix to warm the cached `location` when nothing is feeding it continuously
    /// (used so "Save location when marking plates" works without a map or route tracking).
    /// No-op when continuous updates are running, a fresh-enough fix is cached, or a
    /// one-shot is already in flight.
    func requestOneShotLocationIfStale(maxAge: TimeInterval) {
        guard isAuthorizedForLocation else { return }
        guard updateHolds.isEmpty else { return }
        guard !oneShotInFlight else { return }
        if let location, Date.now.timeIntervalSince(location.timestamp) <= maxAge {
            return
        }
        oneShotInFlight = true
        locationManager.requestLocation()
    }
}

// MARK: - RouteTrackingLocationSource (GPS Step 6)

extension LocationManager: RouteTrackingLocationSource {
    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        $location.eraseToAnyPublisher()
    }

    var locationAuthorizationPublisher: AnyPublisher<Bool, Never> {
        $authorizationStatus
            .map { $0 == .authorizedWhenInUse || $0 == .authorizedAlways }
            .eraseToAnyPublisher()
    }

    /// Automotive tuning while a trip tracks; restored to map-grade defaults when it stops.
    /// GPS Step 8 — background updates stay on only while tracking, with the visible
    /// indicator for user trust. Requires the `location` UIBackgroundMode (Info.plist);
    /// When-In-Use suffices because the session always starts foregrounded (trip start tap).
    func beginRouteTracking() {
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        startUpdatingLocation(hold: Self.routeTrackingHold)
    }

    func endRouteTracking() {
        stopUpdatingLocation(hold: Self.routeTrackingHold)
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .other
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            location = locations.last
            oneShotInFlight = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            oneShotInFlight = false
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let newStatus = manager.authorizationStatus
            authorizationStatus = newStatus
            // Start updates only when a grant lands for a prompt we triggered — open maps
            // have no explicit hook for this transition and rely on it for the location dot.
            if didRequestAuthorization,
               newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                didRequestAuthorization = false
                startUpdatingLocation()
            }
        }
    }
}

