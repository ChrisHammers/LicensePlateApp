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

    // MARK: - §3.1.1 item 22: the upload bound must return, and the queue must resume

    private func drainingCoordinator(
        repo: SyncQueueRepository,
        sessionId: UUID,
        appender: @escaping (TripActivityEvent) async throws -> GameplayEventAppendOutcome
    ) -> SyncCoordinator {
        let coordinator = SyncCoordinator(repository: repo)
        coordinator.setCanonicalSessionPublisher { _ in }
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setGameplayEventAppender(appender)
        return coordinator
    }

    private func queueRow(_ ctx: ModelContext, eventId: String) throws -> SyncQueueItemEntity? {
        try ctx.fetch(FetchDescriptor<SyncQueueItemEntity>()).first { $0.payloadEventId == eventId }
    }

    /// The task-group form awaited the hung callable after its timer fired, so one stuck
    /// upload wedged `gameplayFlushInProgress` for the process and every later flush
    /// silently no-op'd — a device that kept receiving but never sent (one-way sync).
    @Test func aHungUploadTimesOutMarksTheRowFailedAndReleasesTheFlushGate() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let sessionId = UUID()
        var uploads = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            uploads += 1
            if uploads == 1 {
                // A callable that never answers AND ignores cancellation — like a wedged
                // httpsCallable. A plain Task.sleep would not do: the old task-group form
                // cancelled its children and drained them, so a cancellable hang would have
                // let the OLD code return too and this test would prove nothing. Awaiting a
                // detached task's value is not cancellation-aware; the 20 s sleep outlives
                // the test harmlessly.
                let hang = Task.detached { try? await Task.sleep(nanoseconds: 20_000_000_000) }
                await hang.value
            }
            return .accepted(lateReplay: false)
        }
        coordinator.setGameplayAppendRemoteTimeoutForTesting(nanoseconds: 50_000_000)

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-hung")
        let started = Date()
        await coordinator.processPendingSyncItems()
        #expect(Date().timeIntervalSince(started) < 5, "the flush must return once the bound fires (the old form waited the full 20 s hang)")
        #expect(uploads == 1)

        let row = try queueRow(ctx, eventId: "evt-hung")
        #expect(row?.state == SyncQueueItemState.failed.rawValue, "a timed-out upload is a retryable failure, not a verdict")
        #expect(row?.nextRetryAt != nil)
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-hung"))

        // The gate is free: make the row due and the next flush uploads it.
        row?.nextRetryAt = .distantPast
        try ctx.save()
        await coordinator.processPendingSyncItems()
        #expect(uploads == 2, "a second flush must run — the first one's gate was released")
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-hung") == false)
    }

    /// Characterization, not a regression test: the coordinator half of the purge gate
    /// (suspended = no upload, resumed = the same row drains) behaved this way before the
    /// `defer` fix in `FirebaseAuthService`; what the fix guarantees — that resume runs even
    /// when the sign-out throws after the purge — lives in a Firebase-bound singleton and is
    /// covered by the device trace (`queue suspended for purge` / `queue resumed after purge`).
    @Test func aSuspendedQueueUploadsNothingAndDrainsOnceResumed() async throws {
        let ctx = try makeContext()
        let repo = SyncQueueRepository.shared
        repo.setModelContext(ctx)
        let sessionId = UUID()
        var uploads = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            uploads += 1
            return .accepted(lateReplay: false)
        }

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-purge")
        coordinator.suspendProcessingForPurge()
        await coordinator.processPendingSyncItems()
        #expect(uploads == 0)
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-purge"))

        coordinator.resumeProcessingAfterPurge()
        await coordinator.processPendingSyncItems()
        #expect(uploads == 1)
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-purge") == false)
    }

}

@MainActor
final class MockUserSyncExecutor: UserSyncExecutorProtocol {
    var syncedUserIds: [String] = []

    func performUserSync(userId: String) async throws {
        syncedUserIds.append(userId)
    }
}
