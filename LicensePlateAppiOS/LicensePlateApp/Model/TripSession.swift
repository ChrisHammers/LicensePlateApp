//
//  TripSession.swift
//  LicensePlateApp
//
//  Gameplay model foundation — new trip/session entity shape (SwiftData-ready; no @Model in Step 01).
//

import Foundation

/// Session/container only: lifecycle, participants, visibility, trip-level status. Region/country scope lives on GameInstance (e.g. LicensePlateGameConfig); board and progress are owned by GameInstance and derived from events; trip-level rollups are provided by projections (e.g. TripRollup).
final class TripSession {
    var id: UUID
    var name: String
    var status: TripSessionState
    var mode: TripMode
    var createdAt: Date
    var createdBy: String?
    var startedAt: Date?
    var endedAt: Date?
    var endedBy: String?
    /// Snapshot of participants (e.g. for display); can be derived from events or stored.
    var participants: [TripParticipant]
    /// Optional location/risk flags for future anti-spam (trip-level metadata; not persisted).
    var riskFlags: [String]?

    init(
        id: UUID = UUID(),
        name: String,
        status: TripSessionState = .created,
        mode: TripMode = .solo,
        createdAt: Date = .now,
        createdBy: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        endedBy: String? = nil,
        participants: [TripParticipant] = [],
        riskFlags: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.mode = mode
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedBy = endedBy
        self.participants = participants
        self.riskFlags = riskFlags
    }
}
