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
        try park(id: id, nextRetryAt: nextRetryAt, spendsAttempt: true)
    }

    /// Policy hold: park the row, spend nothing. See the protocol doc for why FR-28
    /// rejections must not consume the budget that `markFailed` exists to count down.
    func markHeld(id: String, nextRetryAt: Date?) throws {
        try park(id: id, nextRetryAt: nextRetryAt, spendsAttempt: false)
    }

    func markCancelled(id: String) throws {
        try updateState(id: id, state: .cancelled)
    }

    func markRejected(id: String) throws {
        try updateState(id: id, state: .rejected)
    }

    func markGameplayItemsRecovered(ids: [String]) throws {
        guard let ctx = modelContext, !ids.isEmpty else { return }
        let idSet = Set(ids)
        let cancelledState = SyncQueueItemState.cancelled.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.state == cancelledState }
        )
        let rows = try ctx.fetch(descriptor).filter { idSet.contains($0.id) }
        guard !rows.isEmpty else { return }
        let now = Date()
        for row in rows {
            row.state = SyncQueueItemState.recovered.rawValue
            row.updatedAt = now
        }
        try ctx.save()
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

    /// COPPA FR-28 consent resume: a child-restriction hold parks the row an hour out,
    /// which is correct while the restriction lasts and wrong the moment it lifts —
    /// `fetchFailedRetryDue()` would skip the whole backlog until the hour elapsed.
    /// Clearing the stamp makes the next flush see them. Universal (child and adult).
    @discardableResult
    func clearGameplayRetryBackoff() throws -> Int {
        try unblockFailedGameplayRows(resettingAttempts: false)
    }

    /// Child-account consent only — see the protocol doc. Attempts spent before consent
    /// (historical builds attempted through the hold; timeouts, membership and App Check
    /// failures spend the same counter) would otherwise follow the row past consent and
    /// push it toward the cancel cap. Consent retires the reason, so it retires the cost.
    @discardableResult
    func resetGameplayRetryBudget() throws -> Int {
        try unblockFailedGameplayRows(resettingAttempts: true)
    }

    private func unblockFailedGameplayRows(resettingAttempts: Bool) throws -> Int {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        let failedState = SyncQueueItemState.failed.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> {
                $0.kind == gameplayKind && $0.state == failedState
            }
        )
        let rows = try ctx.fetch(descriptor).filter {
            $0.nextRetryAt != nil || (resettingAttempts && $0.attemptCount > 0)
        }
        guard !rows.isEmpty else { return 0 }
        let now = Date()
        for row in rows {
            row.nextRetryAt = nil
            if resettingAttempts {
                row.attemptCount = 0
            }
            row.updatedAt = now
        }
        try ctx.save()
        return rows.count
    }

    func unrecoveredCancelledGameplayItems() throws -> [SyncQueueItem] {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.kind == gameplayKind }
        )
        let entities = try ctx.fetch(descriptor)
        let completedState = SyncQueueItemState.completed.rawValue
        let rejectedState = SyncQueueItemState.rejected.rawValue
        // Two disqualifiers, both permanent:
        //   `completed` — the upload already landed; re-enqueuing duplicates it.
        //   `rejected`  — the server refused this event for good; re-enqueuing would push
        //                 back data it deliberately refused or deleted (FR-30 retention).
        let settledEventIds = Set(
            entities
                .filter { $0.state == completedState || $0.state == rejectedState }
                .compactMap { $0.payloadEventId }
        )
        let cancelledState = SyncQueueItemState.cancelled.rawValue
        return entities
            .filter { entity in
                entity.state == cancelledState
                    && entity.payloadEventId.map { !settledEventIds.contains($0) } == true
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map { toItem($0) }
    }

    func nonTerminalGameplaySessionIds() throws -> [String] {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        let gameplayKind = SyncQueueItemKind.gameplayEvent.rawValue
        let descriptor = FetchDescriptor<SyncQueueItemEntity>(
            predicate: #Predicate<SyncQueueItemEntity> { $0.kind == gameplayKind }
        )
        let nonTerminalStates: Set<String> = [
            SyncQueueItemState.pending.rawValue,
            SyncQueueItemState.inProgress.rawValue,
            SyncQueueItemState.failed.rawValue
        ]
        var seen = Set<String>()
        var ordered: [String] = []
        for entity in try ctx.fetch(descriptor).sorted(by: { $0.createdAt < $1.createdAt }) {
            guard nonTerminalStates.contains(entity.state),
                  let sessionId = entity.payloadSessionId,
                  !sessionId.isEmpty,
                  seen.insert(sessionId).inserted else { continue }
            ordered.append(sessionId)
        }
        return ordered
    }

    /// Hard sign-out: delete all queue rows and remote sync metadata without uploading.
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        try ctx.delete(model: SyncQueueItemEntity.self)
        try ctx.delete(model: RemoteSyncMetadataEntity.self)
        try ctx.save()
    }

    // MARK: - Private

    private func park(id: String, nextRetryAt: Date?, spendsAttempt: Bool) throws {
        guard let ctx = modelContext else { throw SyncQueueRepositoryError.noModelContext }
        guard let entity = try fetchEntity(id: id, context: ctx) else { return }
        entity.state = SyncQueueItemState.failed.rawValue
        entity.nextRetryAt = nextRetryAt
        entity.updatedAt = Date()
        if spendsAttempt {
            entity.attemptCount += 1
        }
        try ctx.save()
    }

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
