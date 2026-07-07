//
//  TripRoutePointEntity.swift
//  LicensePlateApp
//
//  GPS Step 7 — persisted route point for a trip's ribbon. Per-device telemetry:
//  local-only, never synced to Firestore, not part of the gameplay event log.
//  Lands in SchemaVersion21.
//

import Foundation
import SwiftData

@Model
final class TripRoutePointEntity {
    @Attribute(.unique) var id: String
    var tripSessionId: String
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        tripSessionId: String,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        timestamp: Date
    ) {
        self.id = id
        self.tripSessionId = tripSessionId
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}
