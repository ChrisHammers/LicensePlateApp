//
//  GameInstance.swift
//  LicensePlateApp
//
//  Gameplay model foundation — a game run within a trip session (SwiftData-ready; no @Model in Step 01).
//  Step 07.5 — commonConfig + game-specific payload envelope.
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
    /// Snapshot of rules for this run. Kept for backward compat; new config lives in commonConfig + payload.
    var ruleSet: GameRuleSet
    /// Step 07.5 — Common config (lifecycle, mode, scoring, lock, tracking, voice).
    var commonConfig: CommonGameConfig
    /// Step 07.5 — Game-specific payload type (e.g. "license_plate").
    var gameSpecificPayloadType: String?
    /// Step 07.5 — Version of game-specific payload schema.
    var gameSpecificPayloadVersion: String?
    /// Step 07.5 — Encoded game-specific config (e.g. LicensePlateGameConfig). Decode where needed.
    var gameSpecificPayloadData: Data?
    /// Step 6.9.1 — Teams for this game (e.g. for team-based scoring). Empty when not using teams.
    var teams: [TripTeam]

    init(
        id: UUID = UUID(),
        definitionId: String,
        sessionId: UUID,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        ruleSet: GameRuleSet,
        commonConfig: CommonGameConfig = CommonGameConfig(),
        gameSpecificPayloadType: String? = nil,
        gameSpecificPayloadVersion: String? = nil,
        gameSpecificPayloadData: Data? = nil,
        teams: [TripTeam] = []
    ) {
        self.id = id
        self.definitionId = definitionId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ruleSet = ruleSet
        self.commonConfig = commonConfig
        self.gameSpecificPayloadType = gameSpecificPayloadType
        self.gameSpecificPayloadVersion = gameSpecificPayloadVersion
        self.gameSpecificPayloadData = gameSpecificPayloadData
        self.teams = teams
    }

    /// Decodes LicensePlateGameConfig from gameSpecificPayloadData when definitionId is license_plate. Returns nil otherwise.
    func licensePlateConfig() -> LicensePlateGameConfig? {
        guard definitionId == GameType.licensePlate.rawValue,
              let data = gameSpecificPayloadData else { return nil }
        return try? JSONDecoder().decode(LicensePlateGameConfig.self, from: data)
    }
}
