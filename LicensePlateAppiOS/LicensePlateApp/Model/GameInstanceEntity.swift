//
//  GameInstanceEntity.swift
//  LicensePlateApp
//
//  SwiftData persistence for a game run within a trip session.
//

import Foundation
import SwiftData

/// Persisted game instance. Use with GameInstance (domain) via encode/decode for ruleSetData and commonConfigData.
@Model
final class GameInstanceEntity {
    var id: String
    var definitionId: String
    var sessionId: String
    var startedAt: Date
    var endedAt: Date?
    /// Encoded GameRuleSet (JSON); optional for migration. Kept for backward compat when commonConfigData is nil.
    var ruleSetData: Data?
    /// Step 07.5 — Encoded CommonGameConfig; nil on legacy rows.
    var commonConfigData: Data?
    /// Step 07.5 — Game-specific payload type (e.g. "license_plate").
    var gameSpecificPayloadType: String?
    /// Step 07.5 — Version of game-specific payload schema.
    var gameSpecificPayloadVersion: String?
    /// Step 07.5 — Encoded game-specific config (e.g. LicensePlateGameConfig).
    var gameSpecificPayloadData: Data?
    /// Step 6.9.1 — Encoded [TripTeam] for this game. Nil when empty.
    var teamsData: Data?
    /// Step 13.2 — Latest fairness-banner ack (rejection event time); local + synced via Firebase subdoc per user.
    var fairnessUiLastAckAt: Date?

    init(
        id: String,
        definitionId: String,
        sessionId: String,
        startedAt: Date,
        endedAt: Date? = nil,
        ruleSetData: Data? = nil,
        commonConfigData: Data? = nil,
        gameSpecificPayloadType: String? = nil,
        gameSpecificPayloadVersion: String? = nil,
        gameSpecificPayloadData: Data? = nil,
        teamsData: Data? = nil,
        fairnessUiLastAckAt: Date? = nil
    ) {
        self.id = id
        self.definitionId = definitionId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ruleSetData = ruleSetData
        self.commonConfigData = commonConfigData
        self.gameSpecificPayloadType = gameSpecificPayloadType
        self.gameSpecificPayloadVersion = gameSpecificPayloadVersion
        self.gameSpecificPayloadData = gameSpecificPayloadData
        self.teamsData = teamsData
        self.fairnessUiLastAckAt = fairnessUiLastAckAt
    }
}
