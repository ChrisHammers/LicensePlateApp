//
//  TripActivityEvent.swift
//  LicensePlateApp
//
//  Gameplay model foundation — event log entry for analytics and audit (trip started, region found, trip ended, etc.).
//

import Foundation

/// Kind of activity event in a trip session.
enum TripActivityEventKind: String, Codable, CaseIterable, Sendable {
    case tripStarted = "trip_started"
    case tripEnded = "trip_ended"
    case regionFound = "region_found"
    case participantJoined = "participant_joined"
    case participantLeft = "participant_left"
    case gameStarted = "game_started"
    case gameEnded = "game_ended"
}

/// A single event in the trip lifecycle. Room for analytics and audit.
struct TripActivityEvent: Codable, Identifiable, Sendable {
    var id: String
    var sessionId: UUID
    var kind: TripActivityEventKind
    var timestamp: Date
    /// User id who performed the action, if applicable.
    var actorId: String?
    /// Optional JSON-like payload for event-specific data.
    var payload: [String: String]?

    init(
        id: String = UUID().uuidString,
        sessionId: UUID,
        kind: TripActivityEventKind,
        timestamp: Date = .now,
        actorId: String? = nil,
        payload: [String: String]? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.kind = kind
        self.timestamp = timestamp
        self.actorId = actorId
        self.payload = payload
    }
}
