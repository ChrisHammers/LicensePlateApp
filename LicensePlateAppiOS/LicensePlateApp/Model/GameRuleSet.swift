//
//  GameRuleSet.swift
//  LicensePlateApp
//
//  Gameplay model foundation — generic rules for a game type (scoring, time limits, etc.).
//

import Foundation

/// Rules for a game type. Kept generic so different games can attach different rule payloads.
struct GameRuleSet: Codable, Sendable {
    /// Game definition id this rule set applies to.
    var gameDefinitionId: String
    /// Optional JSON-like payload for game-specific rules (e.g. scoring weights, time limits).
    var payload: [String: String]?

    init(gameDefinitionId: String, payload: [String: String]? = nil) {
        self.gameDefinitionId = gameDefinitionId
        self.payload = payload
    }
}
