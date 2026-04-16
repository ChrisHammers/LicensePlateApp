//
//  XpLedgerMapper.swift
//  LicensePlateApp
//
//  Pure mapping between SwiftData entities and domain values (no ModelContext).
//

import Foundation
import SwiftData

enum XpLedgerMapper {

    static func encodeMetadata(_ metadata: [String: String]?) -> Data? {
        metadata.flatMap { try? JSONEncoder().encode($0) }
    }

    static func decodeMetadata(_ data: Data?) -> [String: String]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func toDomain(_ entity: XpLedgerEventEntity) throws -> XpLedgerEvent {
        guard let grantKind = XpGrantKind(rawValue: entity.grantKind) else {
            throw XpLedgerMapperError.invalidGrantKind(entity.grantKind)
        }
        guard let status = XpLedgerStatus(rawValue: entity.status) else {
            throw XpLedgerMapperError.invalidStatus(entity.status)
        }
        guard let reasonCode = XpReasonCode(rawValue: entity.reasonCode) else {
            throw XpLedgerMapperError.invalidReasonCode(entity.reasonCode)
        }
        guard let sessionId = UUID(uuidString: entity.sessionId) else {
            throw XpLedgerMapperError.invalidUUID(field: "sessionId", value: entity.sessionId)
        }
        guard let gameInstanceId = UUID(uuidString: entity.gameInstanceId) else {
            throw XpLedgerMapperError.invalidUUID(field: "gameInstanceId", value: entity.gameInstanceId)
        }
        return XpLedgerEvent(
            id: entity.id,
            userId: entity.userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            sourceEventId: entity.sourceEventId,
            sourceEventType: entity.sourceEventType,
            itemId: entity.itemId,
            grantKind: grantKind,
            status: status,
            xpDelta: entity.xpDelta,
            reasonCode: reasonCode,
            xpUniquenessKey: entity.xpUniquenessKey,
            createdAt: entity.createdAt,
            resolvedAt: entity.resolvedAt,
            metadata: decodeMetadata(entity.metadataData)
        )
    }

    static func toEntity(_ event: XpLedgerEvent) -> XpLedgerEventEntity {
        XpLedgerEventEntity(
            id: event.id,
            userId: event.userId,
            sessionId: event.sessionId.uuidString,
            gameInstanceId: event.gameInstanceId.uuidString,
            sourceEventId: event.sourceEventId,
            sourceEventType: event.sourceEventType,
            itemId: event.itemId,
            grantKind: event.grantKind.rawValue,
            status: event.status.rawValue,
            xpDelta: event.xpDelta,
            reasonCode: event.reasonCode.rawValue,
            xpUniquenessKey: event.xpUniquenessKey,
            createdAt: event.createdAt,
            resolvedAt: event.resolvedAt,
            metadataData: encodeMetadata(event.metadata)
        )
    }

    static func toDomain(_ entity: DiscoveryResolutionEntity) throws -> DiscoveryResolution {
        guard let finalOutcome = DiscoveryResolutionOutcome(rawValue: entity.finalOutcome) else {
            throw XpLedgerMapperError.invalidDiscoveryResolutionOutcome(entity.finalOutcome)
        }
        guard let tripScoring = TripScoringOutcome(rawValue: entity.tripScoringOutcome) else {
            throw XpLedgerMapperError.invalidTripScoringOutcome(entity.tripScoringOutcome)
        }
        guard let personal = PersonalHistoryOutcome(rawValue: entity.personalHistoryOutcome) else {
            throw XpLedgerMapperError.invalidPersonalHistoryOutcome(entity.personalHistoryOutcome)
        }
        guard let xpReason = XpReasonCode(rawValue: entity.xpReason) else {
            throw XpLedgerMapperError.invalidReasonCode(entity.xpReason)
        }
        guard let sessionId = UUID(uuidString: entity.sessionId) else {
            throw XpLedgerMapperError.invalidUUID(field: "sessionId", value: entity.sessionId)
        }
        guard let gameInstanceId = UUID(uuidString: entity.gameInstanceId) else {
            throw XpLedgerMapperError.invalidUUID(field: "gameInstanceId", value: entity.gameInstanceId)
        }
        return DiscoveryResolution(
            resolutionId: entity.resolutionId,
            sourceEventId: entity.sourceEventId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: entity.itemId,
            actorUserId: entity.actorUserId,
            finalOutcome: finalOutcome,
            tripScoringOutcome: tripScoring,
            personalHistoryOutcome: personal,
            finalXpAward: entity.finalXpAward,
            xpReason: xpReason,
            resolvedAgainstEventId: entity.resolvedAgainstEventId,
            serverSequence: entity.serverSequence,
            resolutionVersion: entity.resolutionVersion,
            resolvedAtServer: entity.resolvedAtServer
        )
    }

    static func toEntity(_ resolution: DiscoveryResolution) -> DiscoveryResolutionEntity {
        DiscoveryResolutionEntity(
            resolutionId: resolution.resolutionId,
            sourceEventId: resolution.sourceEventId,
            sessionId: resolution.sessionId.uuidString,
            gameInstanceId: resolution.gameInstanceId.uuidString,
            itemId: resolution.itemId,
            actorUserId: resolution.actorUserId,
            finalOutcome: resolution.finalOutcome.rawValue,
            tripScoringOutcome: resolution.tripScoringOutcome.rawValue,
            personalHistoryOutcome: resolution.personalHistoryOutcome.rawValue,
            finalXpAward: resolution.finalXpAward,
            xpReason: resolution.xpReason.rawValue,
            resolvedAgainstEventId: resolution.resolvedAgainstEventId,
            serverSequence: resolution.serverSequence,
            resolutionVersion: resolution.resolutionVersion,
            resolvedAtServer: resolution.resolvedAtServer
        )
    }
}

enum XpLedgerMapperError: Error, Equatable {
    case invalidGrantKind(String)
    case invalidStatus(String)
    case invalidReasonCode(String)
    case invalidDiscoveryResolutionOutcome(String)
    case invalidTripScoringOutcome(String)
    case invalidPersonalHistoryOutcome(String)
    case invalidUUID(field: String, value: String)
}
