//
//  GameInstance.swift
//  LicensePlateApp
//
//  Gameplay model foundation — a game run within a trip session (SwiftData-ready; no @Model in Step 01).
//

import Foundation

/// A single game played within a trip session (e.g. one license-plate game for that trip).
final class GameInstance {
    var id: UUID
    /// Game type (e.g. license_plate).
    var definitionId: String
    /// Session this game belongs to.
    var sessionId: UUID
    var startedAt: Date
    var endedAt: Date?
    /// Snapshot of rules for this run.
    var ruleSet: GameRuleSet

    init(
        id: UUID = UUID(),
        definitionId: String,
        sessionId: UUID,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        ruleSet: GameRuleSet
    ) {
        self.id = id
        self.definitionId = definitionId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ruleSet = ruleSet
    }
}
