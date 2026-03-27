//
//  GameInstanceRepository.swift
//  LicensePlateApp
//
//  Local-first persistence for GameInstance. Step 03 — repository layer.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class GameInstanceRepository: ObservableObject, GameInstanceRepositoryProtocol {

    static let shared = GameInstanceRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Create

    func create(instance: GameInstance) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let entity = GameInstanceMapper.toEntity(instance)
        ctx.insert(entity)
        try ctx.save()
    }

    func upsert(instance: GameInstance) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let id = instance.id.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id }
        )
        if let existing = try ctx.fetch(descriptor).first {
            let updated = GameInstanceMapper.toEntity(instance)
            existing.definitionId = updated.definitionId
            existing.sessionId = updated.sessionId
            existing.startedAt = updated.startedAt
            existing.endedAt = updated.endedAt
            existing.ruleSetData = updated.ruleSetData
            existing.commonConfigData = updated.commonConfigData
            existing.gameSpecificPayloadType = updated.gameSpecificPayloadType
            existing.gameSpecificPayloadVersion = updated.gameSpecificPayloadVersion
            existing.gameSpecificPayloadData = updated.gameSpecificPayloadData
            existing.teamsData = updated.teamsData
        } else {
            ctx.insert(GameInstanceMapper.toEntity(instance))
        }
        try ctx.save()
    }

    func replaceGamesForSession(sessionId: UUID, instances: [GameInstance]) throws {
        try deleteForSession(sessionId: sessionId)
        for instance in instances {
            try create(instance: instance)
        }
    }

    // MARK: - Fetch

    func fetchByTripSession(sessionId: UUID) throws -> [GameInstance] {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        var descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.sessionId == sid }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        let entities = try ctx.fetch(descriptor)
        return entities.map { GameInstanceMapper.toDomain($0) }
    }

    func gameCount(sessionId: UUID) throws -> Int {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.sessionId == sid }
        )
        return try ctx.fetchCount(descriptor)
    }

    func deleteForSession(sessionId: UUID) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.sessionId == sid }
        )
        let entities = try ctx.fetch(descriptor)
        for entity in entities {
            let instanceId = entity.id
            let snapshotDescriptor = FetchDescriptor<GameScoreSnapshotEntity>(
                predicate: #Predicate<GameScoreSnapshotEntity> { $0.gameInstanceId == instanceId }
            )
            for snapshot in try ctx.fetch(snapshotDescriptor) {
                ctx.delete(snapshot)
            }
            ctx.delete(entity)
        }
        try ctx.save()
    }

    func delete(instanceId: UUID) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let id = instanceId.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id }
        )
        guard let entity = try ctx.fetch(descriptor).first else {
            throw GameInstanceRepositoryError.instanceNotFound(instanceId)
        }
        let snapshotDescriptor = FetchDescriptor<GameScoreSnapshotEntity>(
            predicate: #Predicate<GameScoreSnapshotEntity> { $0.gameInstanceId == id }
        )
        for snapshot in try ctx.fetch(snapshotDescriptor) {
            ctx.delete(snapshot)
        }
        ctx.delete(entity)
        try ctx.save()
    }

    func instance(byId id: UUID) throws -> GameInstance? {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id.uuidString }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return nil }
        return GameInstanceMapper.toDomain(entity)
    }

    // MARK: - Update

    /// Step 07.5 — Persist full instance (commonConfig, payload, ruleSet). Use when config or payload changed.
    func update(instance: GameInstance) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let id = instance.id.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id }
        )
        guard let entity = try ctx.fetch(descriptor).first else {
            throw GameInstanceRepositoryError.instanceNotFound(instance.id)
        }
        let updated = GameInstanceMapper.toEntity(instance)
        entity.ruleSetData = updated.ruleSetData
        entity.commonConfigData = updated.commonConfigData
        entity.gameSpecificPayloadType = updated.gameSpecificPayloadType
        entity.gameSpecificPayloadVersion = updated.gameSpecificPayloadVersion
        entity.gameSpecificPayloadData = updated.gameSpecificPayloadData
        try ctx.save()
    }

    /// Step 07.5 — Set lifecycle to started and lock config for all games in the session.
    func transitionGamesToStarted(sessionId: UUID) throws {
        let instances = try fetchByTripSession(sessionId: sessionId)
        for var instance in instances {
            instance.commonConfig.lifecycleState = .started
            instance.commonConfig.configLocked = true
            instance.commonConfig.configLockReason = .gameStarted
            try update(instance: instance)
        }
    }

    func updateRuleSet(instanceId: UUID, ruleSet: GameRuleSet) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let id = instanceId.uuidString
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id }
        )
        guard let entity = try ctx.fetch(descriptor).first else {
            throw GameInstanceRepositoryError.instanceNotFound(instanceId)
        }
        entity.ruleSetData = try? JSONEncoder().encode(ruleSet)
        try ctx.save()
    }

    func saveScoreSnapshot(instanceId: UUID, snapshot: Data) throws {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let id = instanceId.uuidString
        let instanceDescriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id }
        )
        guard try ctx.fetch(instanceDescriptor).first != nil else {
            throw GameInstanceRepositoryError.instanceNotFound(instanceId)
        }
        let snapshotDescriptor = FetchDescriptor<GameScoreSnapshotEntity>(
            predicate: #Predicate<GameScoreSnapshotEntity> { $0.gameInstanceId == id }
        )
        if let existing = try ctx.fetch(snapshotDescriptor).first {
            existing.snapshotData = snapshot
            existing.createdAt = Date()
        } else {
            let entity = GameScoreSnapshotEntity(gameInstanceId: id, snapshotData: snapshot)
            ctx.insert(entity)
        }
        try ctx.save()
    }
}

enum GameInstanceRepositoryError: Error, LocalizedError {
    case noModelContext
    case instanceNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        case .instanceNotFound(let id): return "Game instance not found: \(id.uuidString)"
        }
    }
}
