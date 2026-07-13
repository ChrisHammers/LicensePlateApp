//
//  TripSessionTeamsEntity.swift
//  LicensePlateApp
//
//  Legacy entity for session-level teams. Teams moved to GameInstance; this type is
//  retained in-source for reference only and is not part of CurrentSchema.
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
