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

    @Test func hasPendingOrRetryDueGameplayItemsReflectsQueue() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        #expect(try repo.hasPendingOrRetryDueGameplayItems() == false)

        let sessionId = UUID()
        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "e-drain-test")
        #expect(try repo.hasPendingOrRetryDueGameplayItems() == true)

        let pending = try repo.fetchPending(limit: 1)
        try repo.markCompleted(id: pending[0].id)
        #expect(try repo.hasPendingOrRetryDueGameplayItems() == false)

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "e-drain-test-2")
        let pending2 = try repo.fetchPending(limit: 1)
        try repo.markFailed(id: pending2[0].id, nextRetryAt: Date().addingTimeInterval(3600))
        #expect(try repo.hasPendingOrRetryDueGameplayItems() == false)

        try repo.markFailed(id: pending2[0].id, nextRetryAt: Date().addingTimeInterval(-60))
        #expect(try repo.hasPendingOrRetryDueGameplayItems() == true)
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

    // MARK: - COPPA F-6 (FR-28): unconsented-child gameplay hold

    @Test func gameplayItemsHoldWhileChildSyncPaused() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)
        coordinator.setGameplayCloudSyncHoldProvider { true }

        try coordinator.enqueueForSync(sessionId: UUID(), eventId: "evt-child-hold")
        await coordinator.processPendingSyncItems()

        // Queued events simply hold — still pending, never attempted or cancelled.
        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].state == .pending)
        #expect(pending[0].payloadEventId == "evt-child-hold")
    }

    @Test func userProfileSyncStillRunsWhileGameplayHeld() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let mockExecutor = MockUserSyncExecutor()
        let coordinator = SyncCoordinator(repository: repo, userSyncExecutor: mockExecutor)
        coordinator.setGameplayCloudSyncHoldProvider { true }

        // FR-27: the declared child account may still sync its own profile.
        try coordinator.enqueueUserProfileSync(userId: "user-child")
        await coordinator.processPendingSyncItems()

        #expect(mockExecutor.syncedUserIds == ["user-child"])
        #expect(try repo.fetchPending(limit: 10).isEmpty)
    }

    @Test func gameplayItemsResumeWhenHoldLifts() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        let coordinator = SyncCoordinator(repository: repo)

        var held = true
        coordinator.setGameplayCloudSyncHoldProvider { held }

        try coordinator.enqueueForSync(sessionId: UUID(), eventId: "evt-resume")
        await coordinator.processPendingSyncItems()
        #expect(try repo.fetchPending(limit: 10).count == 1)

        // Consent (family admission) lifts the hold; the same flush path drains the
        // queue (the local event no longer exists here, so the item completes).
        held = false
        await coordinator.processPendingSyncItems()
        #expect(try repo.fetchPending(limit: 10).isEmpty)
    }
}

@MainActor
final class MockUserSyncExecutor: UserSyncExecutorProtocol {
    var syncedUserIds: [String] = []

    func performUserSync(userId: String) async throws {
        syncedUserIds.append(userId)
    }
}
