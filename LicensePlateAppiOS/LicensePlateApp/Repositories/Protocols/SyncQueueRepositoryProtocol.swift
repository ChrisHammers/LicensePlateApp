//
//  SyncQueueRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 06 — Protocol for sync queue persistence. Enables test doubles.
//

import Foundation
import SwiftData

@MainActor
protocol SyncQueueRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    func enqueue(_ item: SyncQueueItem) throws
    func fetchPending(limit: Int) throws -> [SyncQueueItem]
    func fetchFailedRetryDue() throws -> [SyncQueueItem]
    func markInProgress(id: String) throws
    func markCompleted(id: String) throws
    func markFailed(id: String, nextRetryAt: Date?) throws
    func markCancelled(id: String) throws
    func metadata(key: String) throws -> RemoteSyncMetadata?
    func saveMetadata(_ metadata: RemoteSyncMetadata) throws
}
