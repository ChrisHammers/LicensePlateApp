//
//  TripSessionRepository.swift
//  LicensePlateApp
//
//  Local-first persistence for TripSession. Step 03 — repository layer.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class TripSessionRepository: ObservableObject, TripSessionRepositoryProtocol {

    static let shared = TripSessionRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Create / Save

    func create(session: TripSession) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        #if DEBUG
        if DebugPersistenceFlags.shouldForceFailure(for: .create) {
            throw DebugForcedPersistenceError.create
        }
        #endif
        let entity = TripSessionPersistence.toEntity(session)
        ctx.insert(entity)
        try ctx.save()
    }

    func save(session: TripSession) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        #if DEBUG
        if DebugPersistenceFlags.shouldForceFailure(for: .save) {
            throw DebugForcedPersistenceError.save
        }
        #endif
        let id = session.id.uuidString
        let descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.id == id }
        )
        if let existing = try ctx.fetch(descriptor).first {
            TripSessionPersistence.updateEntity(existing, from: session)
        } else {
            ctx.insert(TripSessionPersistence.toEntity(session))
        }
        try ctx.save()
    }

    // MARK: - Load by role

    func loadActiveSessions(userId: String?) throws -> [TripSession] {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let activeStatus = TripSessionState.active.rawValue
        let createdStatus = TripSessionState.created.rawValue
        var descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.status == activeStatus || $0.status == createdStatus }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        var entities = try ctx.fetch(descriptor)
        if let uid = userId {
            let pendingLeaveSessions = (try? PendingTripLeaveRepository.shared.sessionIdsPendingLeave(userId: uid)) ?? []
            entities = entities.filter { entity in
                guard let uuid = UUID(uuidString: entity.id) else { return false }
                if pendingLeaveSessions.contains(uuid) { return false }
                return entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        return entities.map { TripSessionPersistence.toDomain($0) }
    }

    func loadArchivedSessions(userId: String?, limit: Int, includeCancelled: Bool, sortBy: TravelLogSort) throws -> [TripSession] {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let ended = TripSessionState.ended.rawValue
        let cancelled = TripSessionState.cancelled.rawValue
        let descriptor: FetchDescriptor<TripSessionEntity>
        if includeCancelled {
            descriptor = FetchDescriptor<TripSessionEntity>(
                predicate: #Predicate<TripSessionEntity> { $0.status == ended || $0.status == cancelled }
            )
        } else {
            descriptor = FetchDescriptor<TripSessionEntity>(
                predicate: #Predicate<TripSessionEntity> { $0.status == ended }
            )
        }
        var mutableDescriptor = descriptor
        mutableDescriptor.sortBy = [SortDescriptor(\.endedAt, order: sortBy == .endedAtDesc ? .reverse : .forward)]
        mutableDescriptor.fetchLimit = limit
        var entities = try ctx.fetch(mutableDescriptor)
        if let uid = userId {
            entities = entities.filter { entity in
                entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        return entities.map { TripSessionPersistence.toDomain($0) }
    }

    // MARK: - Participant

    func addParticipant(sessionId: UUID, participant: TripParticipant) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let id = sessionId.uuidString
        guard let entity = try fetchEntity(byId: id, context: ctx) else {
            throw TripSessionRepositoryError.sessionNotFound(sessionId)
        }
        var participants = TripSessionPersistence.toDomain(entity).participants
        if !participants.contains(where: { $0.userId == participant.userId }) {
            participants.append(participant)
        }
        entity.participantsData = try? JSONEncoder().encode(participants)
        try ctx.save()
    }

    func removeParticipant(sessionId: UUID, userId: String) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let id = sessionId.uuidString
        guard let entity = try fetchEntity(byId: id, context: ctx) else {
            throw TripSessionRepositoryError.sessionNotFound(sessionId)
        }
        var participants = TripSessionPersistence.toDomain(entity).participants
        participants.removeAll { $0.userId == userId }
        entity.participantsData = participants.isEmpty ? nil : (try? JSONEncoder().encode(participants))
        try ctx.save()
    }

    // MARK: - Status

    func updateStatus(sessionId: UUID, status: TripSessionState) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let id = sessionId.uuidString
        guard let entity = try fetchEntity(byId: id, context: ctx) else {
            throw TripSessionRepositoryError.sessionNotFound(sessionId)
        }
        entity.status = status.rawValue
        if status == .active && entity.startedAt == nil {
            entity.startedAt = Date()
        }
        if status == .ended || status == .cancelled {
            entity.endedAt = entity.endedAt ?? Date()
        }
        try ctx.save()
    }

    // MARK: - Lookup

    func session(byId id: UUID) throws -> TripSession? {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        guard let entity = try fetchEntity(byId: id.uuidString, context: ctx) else { return nil }
        return TripSessionPersistence.toDomain(entity)
    }

    /// Placeholder for future sync; entity does not yet have lastSyncedAt.
    func lastSyncedAt(sessionId: UUID) -> Date? {
        nil
    }

    // MARK: - Helpers

    private func fetchEntity(byId id: String, context: ModelContext) throws -> TripSessionEntity? {
        let descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func participantIds(from participantsData: Data?) -> Set<String> {
        guard let data = participantsData,
              let participants = try? JSONDecoder().decode([TripParticipant].self, from: data) else {
            return []
        }
        return Set(participants.map(\.userId))
    }
}

// MARK: - Domain <-> SwiftData (Trip participation derived from participants; not stored on entity)

private enum TripSessionPersistence {
    static func toEntity(_ session: TripSession) -> TripSessionEntity {
        let participantsData: Data? = encodeParticipants(session.participants)
        return TripSessionEntity(
            id: session.id.uuidString,
            name: session.name,
            status: session.status.rawValue,
            createdAt: session.createdAt,
            createdBy: session.createdBy,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            endedBy: session.endedBy,
            participantsData: participantsData
        )
    }

    static func toDomain(_ entity: TripSessionEntity) -> TripSession {
        let participants = decodeParticipants(entity.participantsData)
        let status = TripSessionState(rawValue: entity.status) ?? .active
        let createdAt = entity.createdAt ?? entity.startedAt ?? Date.distantPast
        return TripSession(
            id: UUID(uuidString: entity.id) ?? UUID(),
            name: entity.name,
            status: status,
            createdAt: createdAt,
            createdBy: entity.createdBy,
            startedAt: entity.startedAt,
            endedAt: entity.endedAt,
            endedBy: entity.endedBy,
            participants: participants,
            riskFlags: nil
        )
    }

    static func updateEntity(_ entity: TripSessionEntity, from session: TripSession) {
        entity.name = session.name
        entity.status = session.status.rawValue
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
        guard let data else { return [] }
        return (try? JSONDecoder().decode([TripParticipant].self, from: data)) ?? []
    }
}

enum TripSessionRepositoryError: Error, LocalizedError {
    case noModelContext
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        case .sessionNotFound(let id): return "Trip session not found: \(id.uuidString)"
        }
    }
}
