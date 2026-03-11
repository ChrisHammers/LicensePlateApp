//
//  TripSessionTeamsEntity.swift
//  LicensePlateApp
//
//  Step 06.5 — Separate entity for session teams. Avoids changing TripSessionEntity (which would break schema version fingerprint).
//

import Foundation
import SwiftData

/// Stores encoded [TripTeam] for a trip session. One-to-one with TripSessionEntity by sessionId.
/// Added in SchemaVersion7 only; TripSessionEntity is unchanged so existing stores migrate without "unknown model version".
@Model
final class TripSessionTeamsEntity {
    /// Session this teams payload belongs to (matches TripSessionEntity.id).
    var sessionId: String
    /// Encoded [TripTeam] (JSON).
    var teamsData: Data?

    init(sessionId: String, teamsData: Data? = nil) {
        self.sessionId = sessionId
        self.teamsData = teamsData
    }
}
