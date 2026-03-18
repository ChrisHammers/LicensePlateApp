//
//  SyncQueueRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 06 — SyncQueueRepository: enqueue, fetch pending/failed, state transitions, metadata.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct SyncQueueRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let ctx = ModelContext(container)
        SyncQueueRepository.shared.setModelContext(ctx)
        return ctx
    }

    @Test func enqueueAndFetchPending() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now,
            payloadSessionId: UUID().uuidString,
            payloadEventId: "evt-1"
        )
        try repo.enqueue(item)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].id == item.id)
        #expect(pending[0].state == .pending)
        #expect(pending[0].payloadEventId == "evt-1")
    }

    @Test func markInProgressThenCompleted() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repo.enqueue(item)

        try repo.markInProgress(id: item.id)
        var pending = try repo.fetchPending(limit: 10)
        #expect(pending.isEmpty)

        try repo.markCompleted(id: item.id)
        pending = try repo.fetchPending(limit: 10)
        #expect(pending.isEmpty)
    }

    @Test func markFailedWithNextRetryAt() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repo.enqueue(item)
        try repo.markInProgress(id: item.id)
        let nextRetry = Date().addingTimeInterval(60)
        try repo.markFailed(id: item.id, nextRetryAt: nextRetry)

        let failedDue = try repo.fetchFailedRetryDue()
        #expect(failedDue.isEmpty) // not yet due

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.isEmpty)
    }

    @Test func fetchFailedRetryDueReturnsItemsWhenDue() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .failed,
            attemptCount: 1,
            createdAt: .now,
            updatedAt: .now,
            nextRetryAt: Date().addingTimeInterval(-10) // in the past
        )
        try repo.enqueue(item)

        let failedDue = try repo.fetchFailedRetryDue()
        #expect(failedDue.count == 1)
        #expect(failedDue[0].id == item.id)
    }

    @Test func markCancelled() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now
        )
        try repo.enqueue(item)
        try repo.markCancelled(id: item.id)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.isEmpty)
    }

    @Test func metadataSaveAndFetch() async throws {
        _ = try makeContext()
        let repo = SyncQueueRepository.shared
        let key = "session:\(UUID().uuidString)"
        let meta = RemoteSyncMetadata(key: key, lastSyncedAt: Date(), valueData: nil)
        try repo.saveMetadata(meta)

        let fetched = try repo.metadata(key: key)
        #expect(fetched != nil)
        #expect(fetched?.key == key)
        #expect(fetched?.lastSyncedAt != nil)
    }

    @Test func queueItemsSurviveRestart() async throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let ctx = ModelContext(container)
        SyncQueueRepository.shared.setModelContext(ctx)

        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now,
            payloadSessionId: UUID().uuidString,
            payloadEventId: "evt-survive"
        )
        try SyncQueueRepository.shared.enqueue(item)
        try ctx.save()

        // Simulate restart: new context on same container (in-memory), re-fetch
        let ctx2 = ModelContext(container)
        SyncQueueRepository.shared.setModelContext(ctx2)
        let pending = try SyncQueueRepository.shared.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].payloadEventId == "evt-survive")
    }
}
