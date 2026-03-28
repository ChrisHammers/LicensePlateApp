//
//  GameInstanceMapper.swift
//  LicensePlateApp
//
//  Maps GameInstance (domain) <-> GameInstanceEntity (SwiftData). Step 03 — repository layer. Step 07.5 — config envelope.
//

import Foundation

enum GameInstanceMapper {

    /// Map domain GameInstance to SwiftData GameInstanceEntity (for insert/update).
    static func toEntity(_ instance: GameInstance) -> GameInstanceEntity {
        let ruleSetData = try? JSONEncoder().encode(instance.ruleSet)
        let commonConfigData = try? JSONEncoder().encode(instance.commonConfig)
        let teamsData = encodeTeams(instance.teams)
        return GameInstanceEntity(
            id: instance.id.uuidString,
            definitionId: instance.definitionId,
            sessionId: instance.sessionId.uuidString,
            startedAt: instance.startedAt,
            endedAt: instance.endedAt,
            ruleSetData: ruleSetData,
            commonConfigData: commonConfigData,
            gameSpecificPayloadType: instance.gameSpecificPayloadType,
            gameSpecificPayloadVersion: instance.gameSpecificPayloadVersion,
            gameSpecificPayloadData: instance.gameSpecificPayloadData,
            teamsData: teamsData,
            fairnessUiLastAckAt: instance.fairnessUiLastAckAt
        )
    }

    /// Map SwiftData GameInstanceEntity to domain GameInstance. Uses commonConfigData when present; else defaults and ruleSetData.
    static func toDomain(_ entity: GameInstanceEntity) -> GameInstance {
        let commonConfig: CommonGameConfig
        if let data = entity.commonConfigData, let decoded = try? JSONDecoder().decode(CommonGameConfig.self, from: data) {
            commonConfig = decoded
        } else {
            commonConfig = CommonGameConfig()
        }
        let ruleSet: GameRuleSet
        if let data = entity.ruleSetData, let decoded = try? JSONDecoder().decode(GameRuleSet.self, from: data) {
            ruleSet = decoded
        } else {
            ruleSet = GameRuleSet(gameDefinitionId: entity.definitionId)
        }
        let teams = decodeTeams(entity.teamsData)
        return GameInstance(
            id: UUID(uuidString: entity.id) ?? UUID(),
            definitionId: entity.definitionId,
            sessionId: UUID(uuidString: entity.sessionId) ?? UUID(),
            startedAt: entity.startedAt,
            endedAt: entity.endedAt,
            ruleSet: ruleSet,
            commonConfig: commonConfig,
            gameSpecificPayloadType: entity.gameSpecificPayloadType,
            gameSpecificPayloadVersion: entity.gameSpecificPayloadVersion,
            gameSpecificPayloadData: entity.gameSpecificPayloadData,
            teams: teams,
            fairnessUiLastAckAt: entity.fairnessUiLastAckAt
        )
    }

    private static func encodeTeams(_ teams: [TripTeam]) -> Data? {
        guard !teams.isEmpty else { return nil }
        return try? JSONEncoder().encode(teams)
    }

    private static func decodeTeams(_ data: Data?) -> [TripTeam] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([TripTeam].self, from: data)) ?? []
    }

    /// Decode score snapshot data to a generic dictionary (for future ScoreSnapshot type).
    static func decodeScoreSnapshot(_ data: Data?) -> [String: String]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Encode a score snapshot (e.g. dictionary or future Codable type) to Data.
    static func encodeScoreSnapshot(_ payload: [String: String]) -> Data? {
        try? JSONEncoder().encode(payload)
    }
}
