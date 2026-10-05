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

    // MARK: - §3.1.1 item 31: a parked upload retries on its own wake-up

    /// An isolated queue (not `SyncQueueRepository.shared`): these tests wait on real time, so a
    /// shared repository could be re-pointed at another test's context mid-wait.
    private func isolatedQueue() throws -> (SyncQueueRepository, ModelContext) {
        let ctx = try makeContext()
        let repo = SyncQueueRepository()
        repo.setModelContext(ctx)
        return (repo, ctx)
    }

    /// Suspends on real time so main-actor tasks (the retry wake-up) can run; returns early once
    /// `done()` holds.
    private func waitOnMainActor(upTo seconds: TimeInterval, until done: () -> Bool = { false }) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !done() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// A coordinator whose monitor reads offline throughout and whose first upload fails -1009.
    private func offlineParkingCoordinator(
        repo: SyncQueueRepository,
        sessionId: UUID,
        onUpload: @escaping () -> Int
    ) -> SyncCoordinator {
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            if onUpload() == 1 {
                throw NSError(domain: NSURLErrorDomain, code: -1009)
            }
            return .accepted(lateReplay: false)
        }
        coordinator.setGameplaySyncOnlineProvider { false }
        // 0.2 s rather than 60 s: the -1009 leaves the row due at once but STOPS the flush, so only
        // the wake-up (the offline probe, base 0.2 s) can make the second upload happen.
        coordinator.setGameplayBackoffBaseSecondsForTesting(0.2)
        return coordinator
    }

    /// A gameplay row enqueued with a given retry budget already spent, so its transient backoff
    /// (`2^attemptCount × base`) is longer than a fresh row's.
    private func enqueueGameplayRow(
        _ repo: SyncQueueRepository,
        sessionId: UUID,
        eventId: String,
        attemptCount: Int = 0,
        createdAt: Date = .now
    ) throws {
        try repo.enqueue(SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: attemptCount,
            createdAt: createdAt,
            updatedAt: createdAt,
            payloadSessionId: sessionId.uuidString,
            payloadEventId: eventId
        ))
    }

    /// The owner's simulator log: `verdict failed(transient) … code=-1009 … eligibleIn=60s`, then
    /// `reachability online=1→0`, and the monitor never reported `0→1` after Wi-Fi came back. Every
    /// wake-up the queue had was gated on that monitor, so the find waited for a relaunch. Here the
    /// monitor reads offline throughout: ONE flush, no reachability edge, no new find — the row's own
    /// wake-up must retry it.
    @Test func aParkedUploadRetriesOnItsOwnWakeUpWhileTheMonitorStaysOffline() async throws {
        let (repo, ctx) = try isolatedQueue()
        let sessionId = UUID()
        var uploads = 0
        let coordinator = offlineParkingCoordinator(repo: repo, sessionId: sessionId) {
            uploads += 1
            return uploads
        }

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-parked")
        await coordinator.processPendingSyncItems()
        #expect(uploads == 1, "the first attempt fails -1009 and parks the row")
        #expect(try queueRow(ctx, eventId: "evt-parked")?.state == SyncQueueItemState.failed.rawValue)

        await waitOnMainActor(upTo: 5) { uploads >= 2 }

        #expect(uploads == 2, "the wake-up retried the row with the monitor still reading offline")
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-parked") == false)
    }

    /// The wake-up must not drain mid-wipe: suspending cancels it. A sign-out that FAILS resumes
    /// processing with the account's rows still queued (item 22), so resuming re-arms the wake-up for
    /// them rather than leaving them to trigger-only retries.
    @Test func suspendingForPurgeCancelsTheRetryWakeUpAndResumingReArmsIt() async throws {
        let (repo, _) = try isolatedQueue()
        let sessionId = UUID()
        var uploads = 0
        let coordinator = offlineParkingCoordinator(repo: repo, sessionId: sessionId) {
            uploads += 1
            return uploads
        }

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-purged")
        await coordinator.processPendingSyncItems()
        #expect(uploads == 1)

        coordinator.suspendProcessingForPurge()
        // Well past the 0.2 s probe plus the wake-up's 0.5 s slack.
        await waitOnMainActor(upTo: 1.5)
        #expect(uploads == 1, "a cancelled wake-up never drains")
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-purged"))

        coordinator.resumeProcessingAfterPurge()
        await waitOnMainActor(upTo: 5) { uploads >= 2 }

        #expect(uploads == 2, "the failed sign-out's resume re-armed the wake-up for the parked row")
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-purged") == false)
    }

    /// Review blocker on item 31. A -1009 proves the request never left the device, so it is not a
    /// verdict on the row: the drain stops at the first one instead of attempting every pending find
    /// (each would fail the same way and park on its own doubling backoff that nothing clears on
    /// reconnect), and the attempted row spends none of the budget the `game not found` cap counts.
    /// The rows stay pending / due, so the reachability edge, foreground or relaunch drains all of
    /// them in order, as before item 31.
    @Test func anOfflineFailureStopsTheDrainAndSpendsNoRetryBudget() async throws {
        let (repo, ctx) = try isolatedQueue()
        let sessionId = UUID()
        var uploadedEventIds: [String] = []
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { event in
            uploadedEventIds.append(event.id)
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
        coordinator.setGameplaySyncOnlineProvider { false }

        let start = Date()
        try enqueueGameplayRow(repo, sessionId: sessionId, eventId: "evt-first", createdAt: start)
        try enqueueGameplayRow(repo, sessionId: sessionId, eventId: "evt-second", createdAt: start.addingTimeInterval(1))
        await coordinator.processPendingSyncItems()

        #expect(uploadedEventIds == ["evt-first"], "one probe per drain, not one per pending find")
        let first = try queueRow(ctx, eventId: "evt-first")
        #expect(first?.state == SyncQueueItemState.failed.rawValue)
        #expect(first?.attemptCount == 0, "an offline attempt spends none of the row's budget")
        #expect(first?.nextRetryAt == nil, "due at once for the next trigger, not after a backoff")
        #expect(try queueRow(ctx, eventId: "evt-second")?.state == SyncQueueItemState.pending.rawValue)
        #expect(try repo.hasPendingOrRetryDueGameplayItems())
    }

    /// Review should-fix on item 31. A monitor stuck at offline while the network is up strands every
    /// NEW find too: the debounce skips it, so it is never attempted, never parked and never armed a
    /// wake-up. The skip now arms one as a probe — no failure, no reachability edge required.
    @Test func aFindSkippedByAStuckOfflineMonitorIsUploadedByTheProbe() async throws {
        let (repo, _) = try isolatedQueue()
        let sessionId = UUID()
        var uploads = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            uploads += 1
            return .accepted(lateReplay: false)
        }
        coordinator.setGameplaySyncOnlineProvider { false }
        coordinator.setGameplayBackoffBaseSecondsForTesting(0.2)

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-skipped")
        coordinator.scheduleDebouncedGameplaySyncFlushIfOnline()
        // 0.65 s debounce (skipped: "offline"), then the 0.2 s probe plus 0.5 s slack.
        await waitOnMainActor(upTo: 5) { uploads >= 1 }

        #expect(uploads == 1)
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-skipped") == false)
    }

    /// Drain-end logic, the FR-28 hold. A row is parked, then the hold goes on. The wake-up fires
    /// ONCE, finds the queue held, and is not re-armed: the parked entry was due before that drain
    /// started, so it is the hold's to resume, not the timer's. (Kept, it would re-fire every 0.5 s.)
    @Test func aRetryWakeUpThatFindsTheQueueHeldFiresOnceAndIsNotReArmed() async throws {
        let (repo, _) = try isolatedQueue()
        let sessionId = UUID()
        var uploads = 0
        var held = false
        var drains = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            uploads += 1
            held = true
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        }
        // Read exactly once at the start of every drain, so it counts them.
        coordinator.setGameplayCloudSyncHoldProvider {
            drains += 1
            return held
        }
        coordinator.setGameplayBackoffBaseSecondsForTesting(0.2)

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-held")
        await coordinator.processPendingSyncItems()
        #expect(uploads == 1)
        #expect(drains == 1)

        // The wake-up fires at ~0.7 s; a spinning one would fire again every 0.5 s after that.
        await waitOnMainActor(upTo: 2.5)

        #expect(drains == 2, "one wake-up drain, then nothing re-armed")
        #expect(uploads == 1)
        #expect(try repo.hasNonTerminalGameplayItem(forEventId: "evt-held"))
    }

    /// Drain-end logic, the re-arm. Two rows park on backoffs of different lengths; the wake-up for
    /// the earlier one retries only that one, and the drain re-arms for the later one — which would
    /// otherwise be stranded until some other trigger.
    @Test func aRowParkedOnALongerBackoffIsRetriedOnAReArmedWakeUp() async throws {
        let (repo, ctx) = try isolatedQueue()
        let sessionId = UUID()
        var attemptsByEventId: [String: Int] = [:]
        var drains = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { event in
            attemptsByEventId[event.id, default: 0] += 1
            if attemptsByEventId[event.id] == 1 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
            return .accepted(lateReplay: false)
        }
        coordinator.setGameplayCloudSyncHoldProvider {
            drains += 1
            return false
        }
        coordinator.setGameplayBackoffBaseSecondsForTesting(0.3)

        let start = Date()
        // Fresh: parks 0.3 s. Three attempts already spent: parks 2^3 × 0.3 = 2.4 s.
        try enqueueGameplayRow(repo, sessionId: sessionId, eventId: "evt-short", createdAt: start)
        try enqueueGameplayRow(repo, sessionId: sessionId, eventId: "evt-long", attemptCount: 3, createdAt: start.addingTimeInterval(1))
        await coordinator.processPendingSyncItems()
        #expect(attemptsByEventId == ["evt-short": 1, "evt-long": 1])

        await waitOnMainActor(upTo: 6) {
            attemptsByEventId["evt-short"] == 2 && attemptsByEventId["evt-long"] == 2
        }

        #expect(attemptsByEventId == ["evt-short": 2, "evt-long": 2])
        #expect(try queueRow(ctx, eventId: "evt-short")?.state == SyncQueueItemState.completed.rawValue)
        #expect(try queueRow(ctx, eventId: "evt-long")?.state == SyncQueueItemState.completed.rawValue)
        #expect(drains == 3, "the first flush, the short row's wake-up, the re-armed one for the long row")

        // Nothing is left parked, so nothing fires again.
        await waitOnMainActor(upTo: 1)
        #expect(drains == 3)
    }

    /// Drain-end logic, the clear. A drain driven by something else (here a direct flush after the
    /// row fell due) retires the last parked row, so it cancels the wake-up still scheduled for it.
    @Test func aDrainThatRetiresTheLastParkedRowCancelsTheScheduledWakeUp() async throws {
        let (repo, ctx) = try isolatedQueue()
        let sessionId = UUID()
        var uploads = 0
        var drains = 0
        let coordinator = drainingCoordinator(repo: repo, sessionId: sessionId) { _ in
            uploads += 1
            if uploads == 1 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
            return .accepted(lateReplay: false)
        }
        coordinator.setGameplayCloudSyncHoldProvider {
            drains += 1
            return false
        }
        // Parks 1 s, so its wake-up is scheduled ~1.5 s out.
        coordinator.setGameplayBackoffBaseSecondsForTesting(1)

        try coordinator.enqueueForSync(sessionId: sessionId, eventId: "evt-cleared")
        await coordinator.processPendingSyncItems()
        #expect(uploads == 1)

        let row = try queueRow(ctx, eventId: "evt-cleared")
        row?.nextRetryAt = .distantPast
        try ctx.save()
        await coordinator.processPendingSyncItems()
        #expect(uploads == 2)
        #expect(drains == 2)

        await waitOnMainActor(upTo: 2.5)
        #expect(drains == 2, "the cancelled wake-up never drained")
    }

    /// §3.1.1 item 31d. A launch flush can run before the queue repository has its ModelContext. The
    /// fetch THREW, which used to read as an empty queue (`flush end verdicts=none … queuedSessions=-1`)
    /// and still ran the profile section, spending its 30 s throttle on nothing. It now skips early,
    /// so the first flush after the context lands still syncs the profile.
    @Test func aFlushBeforeTheQueueHasAContextSkipsWithoutSpendingTheProfileThrottle() async throws {
        let repo = SyncQueueRepository()
        let executor = MockUserSyncExecutor()
        let coordinator = SyncCoordinator(repository: repo, userSyncExecutor: executor)

        await coordinator.processPendingSyncItems()
        #expect(executor.syncedUserIds.isEmpty)

        repo.setModelContext(try makeContext())
        try coordinator.enqueueUserProfileSync(userId: "user-launch")
        await coordinator.processPendingSyncItems()

        #expect(executor.syncedUserIds == ["user-launch"], "the unconfigured flush must not spend the profile throttle")
    }

}

@MainActor
final class MockUserSyncExecutor: UserSyncExecutorProtocol {
    var syncedUserIds: [String] = []

    func performUserSync(userId: String) async throws {
        syncedUserIds.append(userId)
    }
}
