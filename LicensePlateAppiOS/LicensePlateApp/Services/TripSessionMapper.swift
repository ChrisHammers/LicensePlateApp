//
//  TripSessionMapper.swift
//  LicensePlateApp
//
//  Gameplay model foundation — maps TripSession + discoveries to legacy-shaped DTO for gradual UI migration (minimal in Step 01).
//

import Foundation

/// DTO compatible with legacy Trip/FoundRegion for UI that still expects that shape. Used when writing back or displaying in legacy views.
struct LegacyTripDTO {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastUpdated: Date
    var createdBy: String?
    var startedAt: Date?
    var isTripEnded: Bool
    var tripEndedAt: Date?
    var tripEndedBy: String?
    var foundRegions: [FoundRegion]
}

/// Maps new model (TripSession + discoveries) to legacy-shaped DTO. Step 01: minimal implementation for tests and future write-back.
enum TripSessionMapper {
    /// Build a legacy-shaped DTO from a session and its discoveries (e.g. from LegacyTripAdapter result).
    static func toLegacyDTO(
        session: TripSession,
        discoveries: [GameDiscovery],
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) -> LegacyTripDTO {
        let foundRegions = discoveries.map { d in
            FoundRegion(
                regionID: d.targetId,
                foundAt: d.discoveredAt,
                inputMethod: d.inputMethod,
                foundBy: d.participantId,
                foundAtLocation: d.location
            )
        }
        return LegacyTripDTO(
            id: session.id,
            name: session.name,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            createdBy: session.createdBy,
            startedAt: session.startedAt,
            isTripEnded: session.status == .ended,
            tripEndedAt: session.endedAt,
            tripEndedBy: session.endedBy,
            foundRegions: foundRegions
        )
    }
}
