//
//  FoundRegion.swift
//  LicensePlateApp
//
//  Step 01 — Extracted from Trip.swift for canonical model. Used by GameDiscovery, RiskAssessmentService, etc.
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

// MARK: - TripActivityEvent payload round-trip (GPS Step 4)

/// Single source for encoding/decoding location on `region_found` payloads.
/// Record side uses `payloadFields()`; replay uses `init(payload:)`. Keep in sync with
/// `TripActivityEventPayloadKey.location*`.
extension LocationData {

    /// Decimal places kept for shared coordinates. 3 dp ≈ 110 m — enough to drop a
    /// "found here" pin in the right neighbourhood, not enough to pinpoint a home.
    static let payloadCoordinateDecimalPlaces = 3

    /// Round a coordinate to `payloadCoordinateDecimalPlaces` before it leaves the device.
    static func coarsenedCoordinate(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return degrees }
        let scale = pow(10.0, Double(payloadCoordinateDecimalPlaces))
        return (degrees * scale).rounded() / scale
    }

    /// String fields to merge into a `region_found` payload.
    ///
    /// Deliberately coarse (COPPA remediation F-4 / FR-45): this payload syncs to the shared
    /// trip document and is visible to every trip member, so it carries only a ~110 m rounded
    /// latitude/longitude plus the capture timestamp. Altitude and horizontal/vertical accuracy
    /// are **not** written — no consumer reads them, and together they sharpen a fix well past
    /// what a map pin needs. `init(payload:)` defaults them when absent.
    func payloadFields() -> [String: String] {
        [
            TripActivityEventPayloadKey.locationLatitude: String(Self.coarsenedCoordinate(latitude)),
            TripActivityEventPayloadKey.locationLongitude: String(Self.coarsenedCoordinate(longitude)),
            TripActivityEventPayloadKey.locationTimestamp: String(timestamp.timeIntervalSince1970)
        ]
    }

    /// nil unless latitude and longitude both parse; remaining fields default defensively
    /// (missing accuracy → -1, CoreLocation's invalid marker). Altitude and accuracy are no
    /// longer written by `payloadFields()`, so they normally take those defaults; the reads
    /// remain for events recorded before the precision change.
    init?(payload: [String: String]?) {
        guard let payload,
              let latitude = payload[TripActivityEventPayloadKey.locationLatitude].flatMap(Double.init),
              let longitude = payload[TripActivityEventPayloadKey.locationLongitude].flatMap(Double.init) else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = payload[TripActivityEventPayloadKey.locationAltitude].flatMap(Double.init) ?? 0
        self.horizontalAccuracy = payload[TripActivityEventPayloadKey.locationHorizontalAccuracy].flatMap(Double.init) ?? -1
        self.verticalAccuracy = payload[TripActivityEventPayloadKey.locationVerticalAccuracy].flatMap(Double.init) ?? -1
        let timestampSeconds = payload[TripActivityEventPayloadKey.locationTimestamp].flatMap(Double.init)
        self.timestamp = timestampSeconds.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
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
