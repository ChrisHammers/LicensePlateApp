//
//  TripSessionEntityMapper.swift
//  LicensePlateApp
//
//  Maps TripSession (domain) <-> TripSessionEntity (SwiftData). Step 03 — repository layer.
//

import Foundation

enum TripSessionEntityMapper {

    /// Map domain TripSession to SwiftData TripSessionEntity (for insert/update). Teams and region scope are on GameInstance (Step 6.9.1, 6.9.2).
    static func toEntity(_ session: TripSession) -> TripSessionEntity {
        let participantsData: Data? = encodeParticipants(session.participants)
        return TripSessionEntity(
            id: session.id.uuidString,
            name: session.name,
            status: session.status.rawValue,
            mode: session.mode.rawValue,
            createdAt: session.createdAt,
            createdBy: session.createdBy,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            endedBy: session.endedBy,
            participantsData: participantsData
        )
    }

    /// Map SwiftData TripSessionEntity to domain TripSession. Teams and region scope are on GameInstance (Step 6.9.1, 6.9.2).
    static func toDomain(_ entity: TripSessionEntity) -> TripSession {
        let participants = decodeParticipants(entity.participantsData)
        let status = TripStatus(rawValue: entity.status) ?? .active
        let mode = Self.mapEntityModeToTripMode(entity.mode)
        let createdAt = entity.createdAt ?? entity.startedAt ?? Date.distantPast
        return TripSession(
            id: UUID(uuidString: entity.id) ?? UUID(),
            name: entity.name,
            status: status,
            mode: mode,
            createdAt: createdAt,
            createdBy: entity.createdBy,
            startedAt: entity.startedAt,
            endedAt: entity.endedAt,
            endedBy: entity.endedBy,
            participants: participants,
            riskFlags: nil
        )
    }

    /// Update an existing entity in-place from a domain session (for upsert).
    static func updateEntity(_ entity: TripSessionEntity, from session: TripSession) {
        entity.name = session.name
        entity.status = session.status.rawValue
        entity.mode = session.mode.rawValue
        entity.createdAt = session.createdAt
        entity.createdBy = session.createdBy
        entity.startedAt = session.startedAt
        entity.endedAt = session.endedAt
        entity.endedBy = session.endedBy
        entity.participantsData = encodeParticipants(session.participants)
    }

    private static func encodeParticipants(_ participants: [TripParticipant]) -> Data? {
        guard !participants.isEmpty else { return nil }
        return try? JSONEncoder().encode(participants)
    }

    private static func decodeParticipants(_ data: Data?) -> [TripParticipant] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([TripParticipant].self, from: data)) ?? []
    }

    /// Backward compatibility: stored mode may be legacy (collaborative, competitive, combined). Map to solo or multiplayer.
    private static func mapEntityModeToTripMode(_ raw: String) -> TripMode {
        switch TripMode(rawValue: raw) {
        case .solo: return .solo
        case .multiplayer: return .multiplayer
        case nil:
            // Legacy values: treat as multiplayer (trip had multiple participants or multiple game types).
            switch raw {
            case "collaborative", "competitive", "combined": return .multiplayer
            default: return .solo
            }
        }
    }
}
