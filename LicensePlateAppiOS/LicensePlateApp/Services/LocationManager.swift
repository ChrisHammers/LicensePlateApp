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
    private var didRequestAuthorization = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Request When In Use authorization.
    func requestAuthorization() {
        didRequestAuthorization = true
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            location = locations.last
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
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
                manager.startUpdatingLocation()
            }
        }
    }
}

