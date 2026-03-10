//
//  GameInstanceMapper.swift
//  LicensePlateApp
//
//  Maps GameInstance (domain) <-> GameInstanceEntity (SwiftData). Step 03 — repository layer.
//

import Foundation

enum GameInstanceMapper {

    /// Map domain GameInstance to SwiftData GameInstanceEntity (for insert/update).
    static func toEntity(_ instance: GameInstance) -> GameInstanceEntity {
        let ruleSetData = (try? JSONEncoder().encode(instance.ruleSet))
        return GameInstanceEntity(
            id: instance.id.uuidString,
            definitionId: instance.definitionId,
            sessionId: instance.sessionId.uuidString,
            startedAt: instance.startedAt,
            endedAt: instance.endedAt,
            ruleSetData: ruleSetData
        )
    }

    /// Map SwiftData GameInstanceEntity to domain GameInstance.
    static func toDomain(_ entity: GameInstanceEntity) -> GameInstance {
        let ruleSet: GameRuleSet
        if let data = entity.ruleSetData, let decoded = try? JSONDecoder().decode(GameRuleSet.self, from: data) {
            ruleSet = decoded
        } else {
            ruleSet = GameRuleSet(gameDefinitionId: entity.definitionId)
        }
        return GameInstance(
            id: UUID(uuidString: entity.id) ?? UUID(),
            definitionId: entity.definitionId,
            sessionId: UUID(uuidString: entity.sessionId) ?? UUID(),
            startedAt: entity.startedAt,
            endedAt: entity.endedAt,
            ruleSet: ruleSet
        )
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
