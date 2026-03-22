//
//  SyncCoordinatorTests.swift
//  LicensePlateAppTests
//
//  Step 06.5 — SyncCoordinator user-profile queue processing.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct SyncCoordinatorTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    @Test func enqueueForSyncCreatesOnePendingItem() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        let sessionId = UUID()
        let eventId = "evt-\(UUID().uuidString)"
        try coordinator.enqueueForSync(sessionId: sessionId, eventId: eventId)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].kind == .gameplayEvent)
        #expect(pending[0].state == .pending)
        #expect(pending[0].payloadSessionId == sessionId.uuidString)
        #expect(pending[0].payloadEventId == eventId)
    }

    @Test func ensureGameplayEventEnqueuedIsIdempotentPerEventId() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        let sessionId = UUID()
        let eventId = "evt-\(UUID().uuidString)"
        try coordinator.ensureGameplayEventEnqueued(sessionId: sessionId, eventId: eventId)
        try coordinator.ensureGameplayEventEnqueued(sessionId: sessionId, eventId: eventId)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].payloadEventId == eventId)
    }

    @Test func enqueueUserProfileSyncCreatesOnePendingItem() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        try coordinator.enqueueUserProfileSync(userId: "user-123")

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].kind == .userProfile)
        #expect(pending[0].payloadData.flatMap { String(data: $0, encoding: .utf8) } == "user-123")
    }

    @Test func processPendingSyncItemsCompletesUserProfileItem() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let mockExecutor = MockUserSyncExecutor()
        let coordinator = SyncCoordinator(repository: repo, userSyncExecutor: mockExecutor)

        try coordinator.enqueueUserProfileSync(userId: "user-123")
        await coordinator.processPendingSyncItems()

        #expect(mockExecutor.syncedUserIds == ["user-123"])
        #expect(try repo.fetchPending(limit: 10).isEmpty)
        #expect((try repo.metadata(key: "user:user-123"))?.lastSyncedAt != nil)
    }
}

@MainActor
final class MockUserSyncExecutor: UserSyncExecutorProtocol {
    var syncedUserIds: [String] = []

    func performUserSync(userId: String) async throws {
        syncedUserIds.append(userId)
    }
}
