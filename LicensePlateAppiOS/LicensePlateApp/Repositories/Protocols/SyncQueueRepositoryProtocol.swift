//
//  SyncQueueRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 06 — Protocol for sync queue persistence. Enables test doubles.
//

import Foundation
import SwiftData

/// Tunable batch size for upload-queue reads. Call sites that omit `limit` use ``SyncQueueRepositoryBatching/defaultPendingFetchLimit``.
enum SyncQueueRepositoryBatching {
    static let defaultPendingFetchLimit: Int = 50
}

@MainActor
protocol SyncQueueRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    func enqueue(_ item: SyncQueueItem) throws
    /// Pass `limit: SyncQueueRepositoryBatching.defaultPendingFetchLimit` when not specified by using ``fetchPending()`` instead.
    func fetchPending(limit: Int) throws -> [SyncQueueItem]
    func fetchFailedRetryDue() throws -> [SyncQueueItem]
    func markInProgress(id: String) throws
    func markCompleted(id: String) throws
    func markFailed(id: String, nextRetryAt: Date?) throws
    func markCancelled(id: String) throws
    func metadata(key: String) throws -> RemoteSyncMetadata?
    func saveMetadata(_ metadata: RemoteSyncMetadata) throws
    /// True if a gameplay sync row exists for this activity event id in pending, inProgress, or failed (retry) state.
    func hasNonTerminalGameplayItem(forEventId eventId: String) throws -> Bool
    /// True if any gameplay row is still `pending`, or `failed` with retry due (used to chain backlog drain passes).
    func hasPendingOrRetryDueGameplayItems() throws -> Bool
    /// After cold start / kill during upload, rows can be stuck `inProgress` and never match `fetchPending`. Clears them to `pending`.
    func resetStuckInProgressSyncItemsToPending() throws
}

extension SyncQueueRepositoryProtocol {
    /// Pending sync rows ordered by `createdAt`, at most ``SyncQueueRepositoryBatching/defaultPendingFetchLimit``.
    func fetchPending() throws -> [SyncQueueItem] {
        try fetchPending(limit: SyncQueueRepositoryBatching.defaultPendingFetchLimit)
    }
}
