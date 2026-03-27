//
//  TripCanonicalWireDTOs.swift
//  LicensePlateApp
//
//  Step 12.5 — Codable wire shapes for Firestore / Cloud Functions trip canonical sync.
//

import Foundation

// MARK: - Session

/// Participant on the wire (Unix seconds for dates — matches JSON / Firestore-friendly payloads).
struct TripParticipantWireItem: Codable, Equatable, Sendable {
    var userId: String
    var role: String
    var joinedAt: Double
    var leftAt: Double?
    var teamId: String?
}

/// Serializable trip session for remote canonical state (not the reference-type domain model).
struct TripSessionWireDTO: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var status: String
    /// Unix timestamp in seconds (JSON-friendly; CF may use Firestore Timestamp when writing docs).
    var createdAt: Double
    var createdBy: String?
    var startedAt: Double?
    var endedAt: Double?
    var endedBy: String?
    var participants: [TripParticipantWireItem]
}

// MARK: - Game instance

struct GameInstanceWireDTO: Codable, Equatable, Sendable {
    var id: String
    var definitionId: String
    var sessionId: String
    var startedAt: Double
    var endedAt: Double?
    var ruleSetDataBase64: String?
    var commonConfigDataBase64: String?
    var gameSpecificPayloadType: String?
    var gameSpecificPayloadVersion: String?
    var gameSpecificPayloadDataBase64: String?
    var teamsDataBase64: String?
}

// MARK: - Activity event

struct TripActivityEventWireDTO: Codable, Equatable, Sendable {
    var id: String
    var sessionId: String
    var kind: String
    var timestamp: Double
    var actorId: String?
    var payload: [String: String]?
}

// MARK: - Bootstrap bundle

struct TripBootstrapWireDTO: Codable, Equatable, Sendable {
    var session: TripSessionWireDTO
    var games: [GameInstanceWireDTO]
    var events: [TripActivityEventWireDTO]
    var syncVersion: Int
    /// When present, more events exist client should fetch with a follow-up (future pagination).
    var nextEventCursor: String?
}

// MARK: - Mapper

enum TripCanonicalMapper {

    static func wireSession(from session: TripSession) -> TripSessionWireDTO {
        let parts = session.participants.map { p -> TripParticipantWireItem in
            TripParticipantWireItem(
                userId: p.userId,
                role: p.role.rawValue,
                joinedAt: p.joinedAt.timeIntervalSince1970,
                leftAt: p.leftAt.map { $0.timeIntervalSince1970 },
                teamId: p.teamId
            )
        }
        return TripSessionWireDTO(
            id: session.id.uuidString,
            name: session.name,
            status: session.status.rawValue,
            createdAt: session.createdAt.timeIntervalSince1970,
            createdBy: session.createdBy,
            startedAt: session.startedAt.map { $0.timeIntervalSince1970 },
            endedAt: session.endedAt.map { $0.timeIntervalSince1970 },
            endedBy: session.endedBy,
            participants: parts
        )
    }

    static func domainSession(from wire: TripSessionWireDTO) -> TripSession {
        let participants: [TripParticipant] = wire.participants.compactMap { item in
            guard let role = TripParticipantRole(rawValue: item.role) else { return nil }
            return TripParticipant(
                userId: item.userId,
                role: role,
                joinedAt: Date(timeIntervalSince1970: item.joinedAt),
                leftAt: item.leftAt.map { Date(timeIntervalSince1970: $0) },
                teamId: item.teamId
            )
        }
        return TripSession(
            id: UUID(uuidString: wire.id) ?? UUID(),
            name: wire.name,
            status: TripSessionState(rawValue: wire.status) ?? .created,
            createdAt: Date(timeIntervalSince1970: wire.createdAt),
            createdBy: wire.createdBy,
            startedAt: wire.startedAt.map { Date(timeIntervalSince1970: $0) },
            endedAt: wire.endedAt.map { Date(timeIntervalSince1970: $0) },
            endedBy: wire.endedBy,
            participants: participants,
            riskFlags: nil
        )
    }

    static func wireGame(from instance: GameInstance) -> GameInstanceWireDTO {
        let entity = GameInstanceMapper.toEntity(instance)
        return GameInstanceWireDTO(
            id: entity.id,
            definitionId: entity.definitionId,
            sessionId: entity.sessionId,
            startedAt: entity.startedAt.timeIntervalSince1970,
            endedAt: entity.endedAt.map { $0.timeIntervalSince1970 },
            ruleSetDataBase64: entity.ruleSetData.flatMap { Self.base64Encode($0) },
            commonConfigDataBase64: entity.commonConfigData.flatMap { Self.base64Encode($0) },
            gameSpecificPayloadType: entity.gameSpecificPayloadType,
            gameSpecificPayloadVersion: entity.gameSpecificPayloadVersion,
            gameSpecificPayloadDataBase64: entity.gameSpecificPayloadData.flatMap { Self.base64Encode($0) },
            teamsDataBase64: entity.teamsData.flatMap { Self.base64Encode($0) }
        )
    }

    static func domainGame(from wire: GameInstanceWireDTO) throws -> GameInstance {
        let ruleData = try wire.ruleSetDataBase64.flatMap { try Self.base64DecodeRequired($0) }
        let commonData = try wire.commonConfigDataBase64.flatMap { try Self.base64DecodeRequired($0) }
        let payloadData = try wire.gameSpecificPayloadDataBase64.flatMap { try Self.base64DecodeRequired($0) }
        let teamsData = try wire.teamsDataBase64.flatMap { try Self.base64DecodeRequired($0) }

        let entity = GameInstanceEntity(
            id: wire.id,
            definitionId: wire.definitionId,
            sessionId: wire.sessionId,
            startedAt: Date(timeIntervalSince1970: wire.startedAt),
            endedAt: wire.endedAt.map { Date(timeIntervalSince1970: $0) },
            ruleSetData: ruleData,
            commonConfigData: commonData,
            gameSpecificPayloadType: wire.gameSpecificPayloadType,
            gameSpecificPayloadVersion: wire.gameSpecificPayloadVersion,
            gameSpecificPayloadData: payloadData,
            teamsData: teamsData
        )
        return GameInstanceMapper.toDomain(entity)
    }

    static func wireEvent(from event: TripActivityEvent) -> TripActivityEventWireDTO {
        TripActivityEventWireDTO(
            id: event.id,
            sessionId: event.sessionId.uuidString,
            kind: event.kind.rawValue,
            timestamp: event.timestamp.timeIntervalSince1970,
            actorId: event.actorId,
            payload: event.payload
        )
    }

    static func domainEvent(from wire: TripActivityEventWireDTO) -> TripActivityEvent? {
        guard let sessionId = UUID(uuidString: wire.sessionId),
              let kind = TripActivityEventKind(rawValue: wire.kind) else {
            return nil
        }
        return TripActivityEvent(
            id: wire.id,
            sessionId: sessionId,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: wire.timestamp),
            actorId: wire.actorId,
            payload: wire.payload
        )
    }

    // MARK: - Base64

    static func base64Encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func base64DecodeRequired(_ string: String) throws -> Data {
        guard let data = Data(base64Encoded: string) else {
            throw TripCanonicalMappingError.invalidBase64
        }
        return data
    }
}

enum TripCanonicalMappingError: Error, Equatable {
    case invalidBase64
}
