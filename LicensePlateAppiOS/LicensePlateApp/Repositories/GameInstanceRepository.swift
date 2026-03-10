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

    func instance(byId id: UUID) throws -> GameInstance? {
        guard let ctx = modelContext else { throw GameInstanceRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<GameInstanceEntity>(
            predicate: #Predicate<GameInstanceEntity> { $0.id == id.uuidString }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return nil }
        return GameInstanceMapper.toDomain(entity)
    }

    // MARK: - Update

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
