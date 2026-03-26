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
    case regionRemoved = "region_removed"
    case discoveryRejected = "discovery_rejected"
    case participantJoined = "participant_joined"
    case participantLeft = "participant_left"
    case gameStarted = "game_started"
    case gameEnded = "game_ended"
}

/// Payload keys for TripActivityEvent (e.g. region_found, region_removed).
enum TripActivityEventPayloadKey {
    static let regionId = "regionId"
    static let gameInstanceId = "gameInstanceId"
    static let participantId = "participantId"
    static let inputMethod = "inputMethod"
    static let discoveredAt = "discoveredAt"
    static let rejectionReason = "rejectionReason"
    static let participantCount = "participantCount"
    static let gameMode = "gameMode"
    /// `region_removed` only: id of the `region_found` `TripActivityEvent` being undone (same as that event’s `id`). Required for partial unfind when multiple finders share a target; omit for legacy “clear all finds for this region”.
    static let removedDiscoveryEventId = "removedDiscoveryEventId"
    /// Optional duplicate of the `region_found` event’s `id` (for sync/debug); replay uses `TripActivityEvent.id` as `GameDiscovery.id` regardless.
    static let discoveryEventId = "discoveryEventId"
}

/// A single event in the trip lifecycle. Room for analytics and audit.
///
/// **Trip vs gameplay payload:** Trip-scoped kinds (e.g. `tripStarted`, `tripEnded`, `participantJoined`, `participantLeft`)
/// do not require `TripActivityEventPayloadKey.gameInstanceId` in the payload. Gameplay kinds that affect a specific game
/// (`regionFound`, `regionRemoved`, `discoveryRejected`, `gameStarted`, `gameEnded`) must include `gameInstanceId` in
/// the payload when persisting or replaying discoveries for that game.
struct TripActivityEvent: Codable, Identifiable, Sendable {
    var id: String
    /// Trip session (container) id — persisted on the entity as the session scope for this event log.
    var sessionId: UUID
    var kind: TripActivityEventKind
    var timestamp: Date
    /// User id who performed the action, if applicable.
    var actorId: String?
    /// Optional JSON-like payload for event-specific data.
    var payload: [String: String]?

    /// Canonical trip container id; same value as `sessionId` (spine naming).
    var tripSessionId: UUID { sessionId }

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
