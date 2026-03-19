//
//  TripSessionTeamsEntity.swift
//  LicensePlateApp
//
//  Step 06.5 — Legacy entity for session-level teams. Step 6.9.1 — Teams moved to GameInstance; this entity is only retained in schema versions 7–11 for migration. Removed from SchemaVersion12.
//

import Foundation
import SwiftData

/// Deprecated: Teams are now on GameInstance (GameInstanceEntity.teamsData). Kept for schema versions 7–11 so migration can run.
@Model
final class TripSessionTeamsEntity {
    var sessionId: String
    var teamsData: Data?

    init(sessionId: String, teamsData: Data? = nil) {
        self.sessionId = sessionId
        self.teamsData = teamsData
    }
}
