//
//  TravelLogEntry.swift
//  LicensePlateApp
//
//  Gameplay model foundation — first-class output for completed trips (Travel Log).
//

import Foundation

/// Summary of a completed trip for the Travel Log. Built from ended TripSession + events in a later step.
struct TravelLogEntry: Codable, Identifiable, Sendable {
    var id: String
    var sessionId: UUID
    var tripName: String
    var endedAt: Date
    /// Human-readable or structured summary (e.g. "12 regions found", participant names).
    var summary: String
    /// Optional location metadata (e.g. centroid or region list).
    var locationMetadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        sessionId: UUID,
        tripName: String,
        endedAt: Date,
        summary: String,
        locationMetadata: [String: String]? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.tripName = tripName
        self.endedAt = endedAt
        self.summary = summary
        self.locationMetadata = locationMetadata
    }
}
