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
        let entity = TripSessionEntityMapper.toEntity(session)
        ctx.insert(entity)
        upsertTeams(sessionId: session.id.uuidString, teams: session.teams, context: ctx)
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
            TripSessionEntityMapper.updateEntity(existing, from: session)
        } else {
            ctx.insert(TripSessionEntityMapper.toEntity(session))
        }
        upsertTeams(sessionId: id, teams: session.teams, context: ctx)
        try ctx.save()
    }

    // MARK: - Load by role

    func loadActiveSessions(userId: String?) throws -> [TripSession] {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let status = TripStatus.active.rawValue
        var descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.status == status }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        var entities = try ctx.fetch(descriptor)
        if let uid = userId {
            entities = entities.filter { entity in
                entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        let teamsMap = try fetchTeamsMap(sessionIds: entities.map(\.id), context: ctx)
        return entities.map { TripSessionEntityMapper.toDomain($0, teamsData: teamsMap[$0.id].flatMap { $0 }) }
    }

    func loadArchivedSessions(userId: String?, limit: Int) throws -> [TripSession] {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let ended = TripStatus.ended.rawValue
        let cancelled = TripStatus.cancelled.rawValue
        var descriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.status == ended || $0.status == cancelled }
        )
        descriptor.sortBy = [SortDescriptor(\.endedAt, order: .reverse)]
        descriptor.fetchLimit = limit
        var entities = try ctx.fetch(descriptor)
        if let uid = userId {
            entities = entities.filter { entity in
                entity.createdBy == uid || participantIds(from: entity.participantsData).contains(uid)
            }
        }
        let teamsMap = try fetchTeamsMap(sessionIds: entities.map(\.id), context: ctx)
        return entities.map { TripSessionEntityMapper.toDomain($0, teamsData: teamsMap[$0.id].flatMap { $0 }) }
    }

    // MARK: - Participant

    func addParticipant(sessionId: UUID, participant: TripParticipant) throws {
        guard let ctx = modelContext else { throw TripSessionRepositoryError.noModelContext }
        let id = sessionId.uuidString
        guard let entity = try fetchEntity(byId: id, context: ctx) else {
            throw TripSessionRepositoryError.sessionNotFound(sessionId)
        }
        var participants = TripSessionEntityMapper.toDomain(entity).participants
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
        var participants = TripSessionEntityMapper.toDomain(entity).participants
        participants.removeAll { $0.userId == userId }
        entity.participantsData = participants.isEmpty ? nil : (try? JSONEncoder().encode(participants))
        try ctx.save()
    }

    // MARK: - Status

    func updateStatus(sessionId: UUID, status: TripStatus) throws {
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
        let teamsData = try? fetchTeamsEntity(bySessionId: id.uuidString, context: ctx)?.teamsData
        return TripSessionEntityMapper.toDomain(entity, teamsData: teamsData)
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

    private func fetchTeamsEntity(bySessionId sessionId: String, context: ModelContext) throws -> TripSessionTeamsEntity? {
        let descriptor = FetchDescriptor<TripSessionTeamsEntity>(
            predicate: #Predicate<TripSessionTeamsEntity> { $0.sessionId == sessionId }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchTeamsMap(sessionIds: [String], context: ModelContext) throws -> [String: Data?] {
        let descriptor = FetchDescriptor<TripSessionTeamsEntity>()
        let all = try context.fetch(descriptor)
        let sessionIdSet = Set(sessionIds)
        return all
            .filter { sessionIdSet.contains($0.sessionId) }
            .reduce(into: [String: Data?]()) { $0[$1.sessionId] = $1.teamsData }
    }

    private func upsertTeams(sessionId: String, teams: [TripTeam], context: ModelContext) {
        let data = TripSessionEntityMapper.encodeTeamsForStorage(teams)
        if let existing = try? fetchTeamsEntity(bySessionId: sessionId, context: context) {
            existing.teamsData = data
        } else if data != nil || !teams.isEmpty {
            context.insert(TripSessionTeamsEntity(sessionId: sessionId, teamsData: data))
        }
    }

    private func participantIds(from participantsData: Data?) -> Set<String> {
        guard let data = participantsData,
              let participants = try? JSONDecoder().decode([TripParticipant].self, from: data) else {
            return []
        }
        return Set(participants.map(\.userId))
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
