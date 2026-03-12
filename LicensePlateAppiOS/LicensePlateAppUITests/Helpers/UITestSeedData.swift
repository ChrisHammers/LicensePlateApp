//
//  UITestSeedData.swift
//  LicensePlateAppUITests
//
//  Step 13 — Deterministic seed data for UI tests. App must inject when launched with seed flags.
//

import Foundation

/// Stable IDs and payloads for seeding. When the app supports launch-argument seeding (e.g. --seedTripWithTwoGames),
/// it can read these values to create in-memory or test DB data so UI tests see predictable content.
enum UITestSeedData {
    static let sessionIdTwoGames = "E621E1F8-C36C-4A1B-9F2D-222222222222"
    static let sessionIdCollaborative = "E621E1F8-C36C-4A1B-9F2D-333333333333"
    static let sessionIdRiskFlags = "E621E1F8-C36C-4A1B-9F2D-666666666666"

    static let tripNameTwoGames = "Multi-Game Trip"
    static let tripNameCollaborative = "Family Road Trip"
    static let tripNameRiskFlags = "In Progress Trip"

    static let fixedTimestamp = 1_700_000_000.0

    /// Payload for "trip with two games" seed. App can decode and create TripSession + GameInstances.
    static func makeTripWithTwoGames() -> [String: Any] {
        [
            "sessionId": sessionIdTwoGames,
            "tripName": tripNameTwoGames,
            "mode": "combined",
            "gameCount": 2,
            "timestamp": fixedTimestamp
        ]
    }

    /// Payload for collaborative trip seed.
    static func makeCollaborativeTrip() -> [String: Any] {
        [
            "sessionId": sessionIdCollaborative,
            "tripName": tripNameCollaborative,
            "mode": "collaborative",
            "participantCount": 2,
            "timestamp": fixedTimestamp
        ]
    }

    /// Payload for trip with risk flags (discoveries with risk).
    static func makeTripWithRiskFlags() -> [String: Any] {
        [
            "sessionId": sessionIdRiskFlags,
            "tripName": tripNameRiskFlags,
            "mode": "solo",
            "hasRiskFlags": true,
            "timestamp": fixedTimestamp
        ]
    }
}
