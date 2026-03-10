//
//  GameInstanceEntity.swift
//  LicensePlateApp
//
//  SwiftData persistence for a game run within a trip session.
//

import Foundation
import SwiftData

/// Persisted game instance. Use with GameInstance (domain) via encode/decode for ruleSetData.
@Model
final class GameInstanceEntity {
    var id: String
    var definitionId: String
    var sessionId: String
    var startedAt: Date
    var endedAt: Date?
    /// Encoded GameRuleSet (JSON); optional for migration.
    var ruleSetData: Data?

    init(
        id: String,
        definitionId: String,
        sessionId: String,
        startedAt: Date,
        endedAt: Date? = nil,
        ruleSetData: Data? = nil
    ) {
        self.id = id
        self.definitionId = definitionId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ruleSetData = ruleSetData
    }
}
