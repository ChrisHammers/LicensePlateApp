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
    /// Server-written when an invite is sent (`sendTripInvite`).
    case participantInvited = "participant_invited"
    case participantLeft = "participant_left"
    case gameStarted = "game_started"
    case gameEnded = "game_ended"
    /// All regions found / completion goal met (may still later transition to `gameEnded`).
    case gameCompleted = "game_completed"
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
    /// Server `srvrej_*` rejection: id of the client’s attempted `region_found`.
    static let clientAttemptEventId = "clientAttemptEventId"
    static let firstFinderParticipantId = "firstFinderParticipantId"
    static let firstFinderDiscoveredAt = "firstFinderDiscoveredAt"
    static let firstFinderEventId = "firstFinderEventId"
    static let serverResolvedAt = "serverResolvedAt"
    static let clientClaimedAt = "clientClaimedAt"
    /// Unix seconds when server accepted this `region_found` (secondary ordering vs same client timestamp).
    static let serverCommittedAt = "serverCommittedAt"
    /// Server `discovery_rejected`: `region_found` id removed by `server_rejected_superseded_by_earlier_timestamp`.
    static let supersededRegionFoundEventId = "supersededRegionFoundEventId"
    /// `participant_left`: `voluntary` | `kicked`
    static let leaveReason = "leaveReason"
    /// `participant_left` when kicked: owner who removed the member
    static let initiatedByUserId = "initiatedByUserId"
    static let fromUserId = "fromUserId"
    static let toUserId = "toUserId"
    static let inviteId = "inviteId"
    static let inviteMethod = "inviteMethod"
    /// `region_found` only, present when the finder's "Save location when marking plates"
    /// setting was on and a fresh fix was cached. Written by `LocationData.payloadFields()`,
    /// read by `LocationData(payload:)`. Syncs to the shared trip document — visible to trip
    /// members in multiplayer. Never log these values.
    ///
    /// **Written set is latitude + longitude + timestamp only**, and the coordinates are
    /// rounded to 3 decimal places (~110 m) before they leave the device (COPPA remediation
    /// F-4 / FR-45). Consumers must tolerate the altitude/accuracy keys being absent.
    static let locationLatitude = "locationLatitude"
    static let locationLongitude = "locationLongitude"
    /// Legacy, read-only: no longer written. Only events recorded before the precision change
    /// carry it; `LocationData(payload:)` defaults it to 0 when absent.
    static let locationAltitude = "locationAltitude"
    /// Legacy, read-only: no longer written. Capture-side accuracy still gates whether a fix is
    /// used at all, but the value is never published. Defaults to -1 when absent.
    static let locationHorizontalAccuracy = "locationHorizontalAccuracy"
    /// Legacy, read-only: no longer written. Defaults to -1 when absent.
    static let locationVerticalAccuracy = "locationVerticalAccuracy"
    /// Unix seconds (same style as `serverCommittedAt`).
    static let locationTimestamp = "locationTimestamp"
    /// Client calendar day `YYYY-MM-DD` for first-find-of-day XP.
    static let xpDayKey = "xpDayKey"
}

/// A single event in the trip lifecycle. Room for analytics and audit.
///
/// **Trip vs gameplay payload:** Trip-scoped kinds (e.g. `tripStarted`, `tripEnded`, `participantJoined`, `participantLeft`)
/// do not require `TripActivityEventPayloadKey.gameInstanceId` in the payload. Gameplay kinds that affect a specific game
/// (`regionFound`, `regionRemoved`, `discoveryRejected`, `gameStarted`, `gameEnded`, `gameCompleted`) must include `gameInstanceId` in
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
