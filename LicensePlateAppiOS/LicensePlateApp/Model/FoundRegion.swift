//
//  FoundRegion.swift
//  LicensePlateApp
//
//  Step 01 — Extracted from Trip.swift for canonical model. Used by GameDiscovery, TripSessionMapper, RiskAssessmentService, etc.
//

import Foundation
import CoreLocation

/// Codable location data extracted from CLLocation
struct LocationData: Codable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var timestamp: Date

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = location.timestamp
    }

    /// Convert back to CLLocation
    func toCLLocation() -> CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
}

/// Metadata for a found region, tracking when, how, and who found it
struct FoundRegion: Codable, Identifiable {
    var id: String { regionID }
    var regionID: String
    var foundAt: Date
    var inputMethod: InputMethod
    var foundBy: String?
    var foundAtLocation: LocationData?

    enum InputMethod: String, Codable, CaseIterable {
        case list
        case voice
    }

    init(
        regionID: String,
        foundAt: Date = .now,
        inputMethod: InputMethod,
        foundBy: String? = nil,
        foundAtLocation: LocationData? = nil
    ) {
        self.regionID = regionID
        self.foundAt = foundAt
        self.inputMethod = inputMethod
        self.foundBy = foundBy
        self.foundAtLocation = foundAtLocation
    }
}
