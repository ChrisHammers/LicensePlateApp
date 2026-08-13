//
//  SyncQueueRepository.swift
//  LicensePlateApp
//
//  Step 06 — Persistence for sync queue and remote metadata. Only layer that touches queue entities.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class SyncQueueRepository: ObservableObject, SyncQueueRepositoryProtocol {

    static let shared = SyncQueueRepository()

    private var modelContext: ModelContext?

    /// `shared` is the app-wide instance; the initializer stays internal so tests can
    /// build an isolated queue instead of mutating shared state.
    init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func enqueue(_ item: SyncQueueItem) throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let entity = toEntity(item)
        ctx.insert(entity)
        try ctx.save()
    }

    /// For the default cap see ``SyncQueueRepositoryBatching/defaultPendingFetchLimit`` (`SyncQueueRepositoryProtocol/fetchPending()`).
    func fetchPending(limit: Int) throws -> [SyncQueueItem] {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let pendingState = SyncQueueItemState.pending.rawValue
        var descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.state == pendingState }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
        descriptor.fetchLimit = limit
        let entities = try ctx.fetch(descriptor)
        return entities.map { toItem($0) }
    }

    func fetchFailedRetryDue() throws -> [SyncQueueItem] {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let failedState = SyncQueueItemState.failed.rawValue
        var descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.state == failedState }
        )
        descriptor.sortBy = [SortDescriptor(\.nextRetryAt, order: .forward)]
        let entities = try ctx.fetch(descriptor)
        let now = Date()
        return entities
            .filter { $0.nextRetryAt == nil || ($0.nextRetryAt ?? .distantFuture) <= now }
            .map { toItem($0) }
    }

    func markInProgress(id: String) throws {
        try updateState(id: id, state: .inProgress)
    }

    func markCompleted(id: String) throws {
        try updateState(id: id, state: .completed)
    }

    func markFailed(id: String, nextRetryAt: Date?) throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        guard let entity = try fetchEntity(id: id, context: ctx) else { return }
        entity.state = SyncQueueItemState.failed.rawValue
        entity.nextRetryAt = nextRetryAt
        entity.updatedAt = Date()
        entity.attemptCount += 1
        try ctx.save()
    }

    func markCancelled(id: String) throws {
        try updateState(id: id, state: .cancelled)
    }

    func metadata(key: String) throws -> RemoteSyncMetadata? {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let searchKey = key
        let descriptor = FetchDescriptor<RemoteSyncMetadataEntity>(
            predicate: #Predicate<RemoteSyncMetadataEntity> { $0.key == searchKey }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return nil }
        return RemoteSyncMetadata(
            key: entity.key,
            lastSyncedAt: entity.lastSyncedAt,
            valueData: entity.valueData
        )
    }

    func saveMetadata(_ metadata: RemoteSyncMetadata) throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let searchKey = metadata.key
        let descriptor = FetchDescriptor<RemoteSyncMetadataEntity>(
            predicate: #Predicate<RemoteSyncMetadataEntity> { $0.key == searchKey }
        )
        if let existing = try ctx.fetch(descriptor).first {
            existing.lastSyncedAt = metadata.lastSyncedAt
            existing.valueData = metadata.valueData
        } else {
            ctx.insert(RemoteSyncMetadataEntity(
                key: metadata.key,
                lastSyncedAt: metadata.lastSyncedAt,
                valueData: metadata.valueData
            ))
        }
        try ctx.save()
    }

    func hasNonTerminalGameplayItem(forEventId eventId: String) throws -> Bool {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        var descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.kind == gameplayKind }
        )
        let entities = try ctx.fetch(descriptor)
        let nonTerminalStates: Set<String> = [
            SyncQueueItemState.pending.rawValue,
            SyncQueueItemState.inProgress.rawValue,
            SyncQueueItemState.failed.rawValue
        ]
        return entities.contains { entity in
            entity.payloadEventId == eventId && nonTerminalStates.contains(entity.state)
        }
    }

    func hasPendingOrRetryDueGameplayItems() throws -> Bool {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        let pendingState = SyncQueueItemState.pending.rawValue
        var pendingDescriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.kind == gameplayKind && $0.state == pendingState }
        )
        pendingDescriptor.fetchLimit = 1
        if try !ctx.fetch(pendingDescriptor).isEmpty {
            return true
        }
        let failedState = SyncQueueItemState.failed.rawValue
        let failedDescriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.kind == gameplayKind && $0.state == failedState }
        )
        let failedRows = try ctx.fetch(failedDescriptor)
        let now = Date()
        return failedRows.contains { row in
            row.nextRetryAt == nil || (row.nextRetryAt ?? .distantFuture) <= now
        }
    }

    func resetStuckInProgressSyncItemsToPending() throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let inProgressState = SyncQueueItemState.inProgress.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.state == inProgressState }
        )
        let stuck = try ctx.fetch(descriptor)
        guard !stuck.isEmpty else { return }
        let pendingState = SyncQueueItemState.pending.rawValue
        let now = Date()
        for entity in stuck {
            entity.state = pendingState
            entity.nextRetryAt = nil
            entity.updatedAt = now
        }
        try ctx.save()
    }

    /// COPPA FR-28 consent resume: a child-restriction rejection parks the row an hour
    /// out (`markFailed(nextRetryAt: +3600)`), which is correct while the restriction
    /// lasts and wrong the moment it lifts — `fetchFailedRetryDue()` would skip the whole
    /// backlog until the hour elapsed. Clearing the stamp makes the next flush see them.
    @discardableResult
    func clearGameplayRetryBackoff() throws -> Int {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        let failedState = SyncQueueItemState.failed.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> {
                $0.kind == gameplayKind && $0.state == failedState
            }
        )
        let rows = try ctx.fetch(descriptor).filter { $0.nextRetryAt != nil }
        guard !rows.isEmpty else { return 0 }
        let now = Date()
        for row in rows {
            row.nextRetryAt = nil
            row.updatedAt = now
        }
        try ctx.save()
        return rows.count
    }

    /// Hard sign-out: delete all queue rows and remote sync metadata without uploading.
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        try ctx.delete(model: SyncQueueItemEntity.self)
        try ctx.delete(model: RemoteSyncMetadataEntity.self)
        try ctx.save()
    }

    // MARK: - Private

    private func updateState(id: String, state: SyncQueueItemState) throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        guard let entity = try fetchEntity(id: id, context: ctx) else { return }
        entity.state = state.rawValue
        entity.updatedAt = Date()
        try ctx.save()
    }

    private func fetchEntity(id: String, context: ModelContext) throws -> SyncQueueItemEntity? {
        let searchId = id
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.id == searchId }
        )
        return try context.fetch(descriptor).first
    }

    private func toEntity(_ item: SyncQueueItem) -> SyncQueueItemEntity {
        SyncQueueItemEntity(
            id: item.id,
            kind: item.kind.rawValue,
            state: item.state.rawValue,
            attemptCount: item.attemptCount,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            nextRetryAt: item.nextRetryAt,
            payloadSessionId: item.payloadSessionId,
            payloadEventId: item.payloadEventId,
            payloadData: item.payloadData
        )
    }

    private func toItem(_ entity: SyncQueueItemEntity) -> SyncQueueItem {
        SyncQueueItem(
            id: entity.id,
            kind: SyncQueueItemKind(rawValue: entity.kind) ?? .gameplayEvent,
            state: SyncQueueItemState(rawValue: entity.state) ?? .pending,
            attemptCount: entity.attemptCount,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            nextRetryAt: entity.nextRetryAt,
            payloadSessionId: entity.payloadSessionId,
            payloadEventId: entity.payloadEventId,
            payloadData: entity.payloadData
        )
    }
}

enum SyncQueueRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "SyncQueueRepository: ModelContext not set"
        }
    }
}
