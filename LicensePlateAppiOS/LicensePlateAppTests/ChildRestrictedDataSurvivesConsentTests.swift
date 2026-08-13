//
//  ChildRestrictedDataSurvivesConsentTests.swift
//  LicensePlateAppTests
//
//  COPPA FR-28: the restricted-child hold promises "local play continues, uploads resume
//  at consent". These suites pin the three ways that promise was broken:
//
//  1. Policy holds spent retry budgets, so a long-restricted child arrived at consent with
//     nothing left and rows were cancelled instead of uploaded.
//  2. Consent resume cleared the backoff stamp but not the budget, and drained before the
//     canonical sessions existed server-side — so first attempts were `game not found`.
//  3. Anything already cancelled was unrecoverable: canonical replay re-uploads only
//     game_started / game_ended / game_completed, never a discovery.
//
//  Everything here is deterministic: injected seams, no Firebase, no wall-clock races.
//

import Foundation
import FirebaseFunctions
import SwiftData
import Testing
@testable import LicensePlateApp

// MARK: - Shared helpers

@MainActor
private func makeQueue() throws -> SyncQueueRepository {
    let schema = Schema(versionedSchema: CurrentSchema.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [config]
    )
    let repository = SyncQueueRepository()
    repository.setModelContext(ModelContext(container))
    return repository
}

@MainActor
@discardableResult
private func enqueueGameplay(
    _ repository: SyncQueueRepository,
    eventId: String,
    sessionId: String = UUID().uuidString
) throws -> String {
    let id = UUID().uuidString
    try repository.enqueue(
        SyncQueueItem(
            id: id,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now,
            payloadSessionId: sessionId,
            payloadEventId: eventId
        )
    )
    return id
}

/// The exact shape of the server's FR-28 refusal (`assertNotUnconsentedChild`).
private func childRestrictionError(reason: String = "unconsented_child") -> NSError {
    NSError(
        domain: FunctionsErrorDomain,
        code: FunctionsErrorCode.failedPrecondition.rawValue,
        userInfo: [FunctionsErrorDetailsKey: ["reason": reason]]
    )
}

private struct TransientError: Error {}

// MARK: - A. Policy holds never consume retry budgets

@MainActor
struct ChildRestrictionHoldBudgetTests {

    /// The root defect: `markFailed` always incremented, so every pre-consent refusal
    /// counted down the same budget the `game not found` cap spends before cancelling.
    @Test func aHeldRowSpendsNothing() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")

        for _ in 0..<25 {
            try repository.markHeld(id: id, nextRetryAt: Date().addingTimeInterval(3600))
        }

        try repository.resetGameplayRetryBudget()
        let row = try #require(try repository.fetchFailedRetryDue().first)
        #expect(row.attemptCount == 0)
    }

    /// A held row is still parked — the hold must not turn into a hot retry loop.
    @Test func aHeldRowIsStillParkedUntilTheBackoffIsCleared() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")

        try repository.markHeld(id: id, nextRetryAt: Date().addingTimeInterval(3600))

        #expect(try repository.fetchPending().isEmpty)
        #expect(try repository.fetchFailedRetryDue().isEmpty)
        #expect(try repository.hasPendingOrRetryDueGameplayItems() == false)
    }

    /// A REAL failure must still count, or nothing would ever give up.
    @Test func aGenuineFailureStillSpendsTheBudget() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")

        try repository.markFailed(id: id, nextRetryAt: nil)
        try repository.markFailed(id: id, nextRetryAt: nil)

        let row = try #require(try repository.fetchFailedRetryDue().first)
        #expect(row.attemptCount == 2)
    }

    /// Holds and failures share one counter, so a mixed history must charge only the
    /// failures — this is the case that used to silently exhaust the cap.
    @Test func holdsAndFailuresShareOneCounterAndOnlyFailuresCharge() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")

        try repository.markHeld(id: id, nextRetryAt: nil)
        try repository.markFailed(id: id, nextRetryAt: nil)
        try repository.markHeld(id: id, nextRetryAt: nil)

        let row = try #require(try repository.fetchFailedRetryDue().first)
        #expect(row.attemptCount == 1)
    }

    /// Child consent restores a full budget even for rows whose attempts were genuine.
    @Test func childConsentResetsEvenGenuinelySpentBudgets() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        for _ in 0..<9 {
            try repository.markFailed(id: id, nextRetryAt: nil)
        }
        #expect(try repository.fetchFailedRetryDue().first?.attemptCount == 9)

        #expect(try repository.resetGameplayRetryBudget() == 1)

        let row = try #require(try repository.fetchFailedRetryDue().first)
        #expect(row.attemptCount == 0)
        #expect(row.nextRetryAt == nil)
    }

    /// R3: the universal path clears the stamp but must NOT erase give-up progress —
    /// that widening is child-only.
    @Test func theUniversalBackoffClearLeavesAttemptCountAlone() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markFailed(id: id, nextRetryAt: Date().addingTimeInterval(3600))
        try repository.markFailed(id: id, nextRetryAt: Date().addingTimeInterval(3600))

        #expect(try repository.clearGameplayRetryBackoff() == 1)

        let row = try #require(try repository.fetchFailedRetryDue().first)
        #expect(row.nextRetryAt == nil)
        #expect(row.attemptCount == 2)
    }

    @Test func resettingBudgetsLeavesUserProfileRowsAlone() throws {
        let repository = try makeQueue()
        let id = UUID().uuidString
        try repository.enqueue(
            SyncQueueItem(
                id: id,
                kind: .userProfile,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadData: "uid".data(using: .utf8)
            )
        )
        try repository.markFailed(id: id, nextRetryAt: nil)

        #expect(try repository.resetGameplayRetryBudget() == 0)
        #expect(try repository.fetchFailedRetryDue().first?.attemptCount == 1)
    }
}

// MARK: - C.1. Durable recovery of cancelled gameplay rows

@MainActor
struct CancelledGameplayRowRecoveryTests {

    @Test func aCancelledRowWithNoCompletedTwinIsRecoverable() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: id)

        let dropped = try repository.unrecoveredCancelledGameplayItems()

        #expect(dropped.map(\.payloadEventId) == ["region_found-1"])
    }

    /// The upload landed by another route (a completed row for the same event). Recovering
    /// it would be a duplicate upload.
    @Test func aCancelledRowIsIgnoredWhenTheEventAlreadyCompletedElsewhere() throws {
        let repository = try makeQueue()
        let cancelled = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: cancelled)
        let completed = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCompleted(id: completed)

        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    @Test func liveAndCompletedRowsAreNotRecoveryCandidates() throws {
        let repository = try makeQueue()
        try enqueueGameplay(repository, eventId: "pending-1")
        let failed = try enqueueGameplay(repository, eventId: "failed-1")
        try repository.markFailed(id: failed, nextRetryAt: nil)
        let done = try enqueueGameplay(repository, eventId: "done-1")
        try repository.markCompleted(id: done)

        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// R1: THE scoping rule. A server verdict is not an FR-28 casualty, and re-uploading it
    /// would push back data the server deliberately refused or deleted.
    @Test func rejectedRowsAreNeverRecoveryCandidates() throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_removed-1")
        try repository.markRejected(id: id)

        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// Belt and braces: even a cancelled row is disqualified once ANY row for the same
    /// event carries a server verdict.
    @Test func aRejectedTwinDisqualifiesACancelledRow() throws {
        let repository = try makeQueue()
        let cancelled = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: cancelled)
        let rejected = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markRejected(id: rejected)

        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// R1b: the pass must self-quench. Without settling, every launch and every join would
    /// re-scan the same cancelled row forever — unbounded new rows, repeated callables.
    @Test func recoveringARowSettlesItSoItIsNeverSeenAgain() async throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: UUID(), kind: .regionFound)
        }

        #expect(coordinator.recoverDroppedGameplayEventRows() == 1)
        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// The unbounded-growth regression, stated directly: repeated passes must not keep
    /// minting rows.
    @Test func repeatedPassesDoNotGrowTheQueue() async throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: UUID(), kind: .regionFound)
        }

        for _ in 0..<10 {
            _ = coordinator.recoverDroppedGameplayEventRows()
        }

        #expect(try repository.fetchPending().count == 1)
    }

    /// A skipped row settles too — it will never be the one that needs healing, so leaving
    /// it cancelled would just re-scan it on every pass forever.
    @Test func aSkippedRowSettlesInsteadOfBeingRescannedForever() async throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-gone")
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { _ in nil }

        #expect(coordinator.recoverDroppedGameplayEventRows() == 0)
        #expect(try repository.unrecoveredCancelledGameplayItems().isEmpty)
    }

    /// End to end through the coordinator: a cancelled discovery comes back as a fresh
    /// pending row with a full budget.
    @Test func recoveryReEnqueuesCancelledDiscoveries() async throws {
        let repository = try makeQueue()
        let sessionId = UUID().uuidString
        let id = try enqueueGameplay(repository, eventId: "region_found-1", sessionId: sessionId)
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: UUID(), kind: .regionFound)
        }

        #expect(coordinator.recoverDroppedGameplayEventRows() == 1)

        let pending = try repository.fetchPending()
        #expect(pending.map(\.payloadEventId) == ["region_found-1"])
        #expect(pending.first?.payloadSessionId == sessionId)
        #expect(pending.first?.attemptCount == 0)
    }

    /// Idempotency: running the pass again must not pile up duplicate rows, because the
    /// first run left a live row that `ensureGameplayEventEnqueued` respects.
    @Test func recoveryIsIdempotent() async throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-1")
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: UUID(), kind: .regionFound)
        }

        #expect(coordinator.recoverDroppedGameplayEventRows() == 1)
        #expect(coordinator.recoverDroppedGameplayEventRows() == 0)
        #expect(coordinator.recoverDroppedGameplayEventRows() == 0)
        #expect(try repository.fetchPending().count == 1)
    }

    /// An event the device no longer has (superseded and deleted) must not be resurrected.
    @Test func recoverySkipsEventsThatNoLongerExistLocally() async throws {
        let repository = try makeQueue()
        let id = try enqueueGameplay(repository, eventId: "region_found-gone")
        try repository.markCancelled(id: id)

        let coordinator = SyncCoordinator(repository: repository)
        coordinator.setLocalGameplayEventProvider { _ in nil }

        #expect(coordinator.recoverDroppedGameplayEventRows() == 0)
        #expect(try repository.fetchPending().isEmpty)
    }
}

// MARK: - B.2. Publish canonical sessions before draining

@MainActor
struct ConsentResumePublishBeforeDrainTests {

    /// Records the order of repository reads and canonical publishes so the ordering
    /// assertion is about observed effects, not timing.
    @MainActor
    fileprivate final class RecordingQueue: SyncQueueRepositoryProtocol {
        var calls: [String] = []
        var nonTerminalSessionIds: [String] = []
        var cancelled: [SyncQueueItem] = []
        var pending: [SyncQueueItem] = []
        var states: [String: SyncQueueItemState] = [:]
        var attemptCounts: [String: Int] = [:]

        func setModelContext(_ context: ModelContext) {}
        func enqueue(_ item: SyncQueueItem) throws { calls.append("enqueue") }
        func fetchPending(limit: Int) throws -> [SyncQueueItem] {
            calls.append("fetchPending")
            defer { pending = [] }
            return pending
        }
        func fetchFailedRetryDue() throws -> [SyncQueueItem] { [] }
        func markInProgress(id: String) throws { states[id] = .inProgress }
        func markCompleted(id: String) throws { states[id] = .completed }
        func markFailed(id: String, nextRetryAt: Date?) throws {
            calls.append("markFailed")
            states[id] = .failed
            attemptCounts[id, default: 0] += 1
        }
        func markHeld(id: String, nextRetryAt: Date?) throws {
            calls.append("markHeld")
            states[id] = .failed
        }
        func markCancelled(id: String) throws {
            calls.append("markCancelled")
            states[id] = .cancelled
        }
        func markRejected(id: String) throws {
            calls.append("markRejected")
            states[id] = .rejected
        }
        func metadata(key: String) throws -> RemoteSyncMetadata? { nil }
        func saveMetadata(_ metadata: RemoteSyncMetadata) throws {}
        func hasNonTerminalGameplayItem(forEventId eventId: String) throws -> Bool { false }
        func hasPendingOrRetryDueGameplayItems() throws -> Bool { false }
        func resetStuckInProgressSyncItemsToPending() throws {}
        func clearGameplayRetryBackoff() throws -> Int {
            calls.append("clearBackoff")
            return 0
        }
        func resetGameplayRetryBudget() throws -> Int {
            calls.append("resetBudget")
            return 0
        }
        func unrecoveredCancelledGameplayItems() throws -> [SyncQueueItem] {
            calls.append("readCancelled")
            return cancelled
        }
        func markGameplayItemsRecovered(ids: [String]) throws {
            calls.append("settleRecovered")
            for id in ids { states[id] = .recovered }
        }
        func nonTerminalGameplaySessionIds() throws -> [String] {
            calls.append("readSessionIds")
            return nonTerminalSessionIds
        }
    }

    /// The race the old resume lost: draining first meant every event hit `game not
    /// found`, because canonical publish is a no-op while restricted and the session had
    /// never reached the server. Publishing first removes the race instead of retrying
    /// through it.
    @Test func childConsentResumePublishesEverySessionBeforeItDrains() async {
        let queue = RecordingQueue()
        let sessionA = UUID()
        let sessionB = UUID()
        queue.nonTerminalSessionIds = [sessionA.uuidString, sessionB.uuidString]

        var published: [UUID] = []
        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setCanonicalSessionPublisher { sessionId in
            queue.calls.append("publish")
            published.append(sessionId)
        }

        await coordinator.resumeGameplaySyncAfterChildConsent()

        #expect(published == [sessionA, sessionB])
        let firstPublish = queue.calls.firstIndex(of: "publish")
        let firstDrain = queue.calls.firstIndex(of: "fetchPending")
        #expect(firstPublish != nil)
        #expect(firstDrain != nil)
        #expect(firstPublish! < firstDrain!)
    }

    /// Full ordering contract: budget reset, then recovery, then publish, then drain.
    /// Recovery must precede the session read or a session whose every row was cancelled
    /// would never be published at all.
    @Test func childConsentResumeRunsItsStepsInTheRequiredOrder() async {
        let queue = RecordingQueue()
        queue.nonTerminalSessionIds = [UUID().uuidString]
        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setCanonicalSessionPublisher { _ in queue.calls.append("publish") }

        await coordinator.resumeGameplaySyncAfterChildConsent()

        let ordered = queue.calls.filter {
            ["resetBudget", "readCancelled", "readSessionIds", "publish", "fetchPending"].contains($0)
        }
        #expect(ordered.prefix(5) == [
            "resetBudget", "readCancelled", "readSessionIds", "publish", "fetchPending"
        ])
    }

    @Test func childConsentResumeWithNothingQueuedIsAPlainFlush() async {
        let queue = RecordingQueue()
        let coordinator = SyncCoordinator(repository: queue)
        var publishCount = 0
        coordinator.setCanonicalSessionPublisher { _ in publishCount += 1 }

        await coordinator.resumeGameplaySyncAfterChildConsent()

        #expect(publishCount == 0)
    }

    /// Occupies the gate with a drain that suspends until `release` is called, so a test
    /// can deterministically arrange "a flush already owns the gate".
    @MainActor
    private final class GateHolder {
        let queue: RecordingQueue
        let coordinator: SyncCoordinator
        private var release: (() -> Void)?

        init(queue: RecordingQueue) {
            self.queue = queue
            self.coordinator = SyncCoordinator(repository: queue)
            let sessionId = UUID()
            coordinator.setLocalGameplayEventProvider { eventId in
                TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
            }
            coordinator.setCanonicalSessionPublisher { _ in self.queue.calls.append("publish") }
            queue.pending = [
                SyncQueueItem(
                    id: "row-hold",
                    kind: .gameplayEvent,
                    state: .pending,
                    attemptCount: 0,
                    createdAt: .now,
                    updatedAt: .now,
                    payloadSessionId: sessionId.uuidString,
                    payloadEventId: "evt-hold"
                )
            ]
            coordinator.setGameplayEventAppender { [weak self] _ in
                guard let self else { return .accepted(lateReplay: false) }
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    self.release = { c.resume() }
                }
                self.queue.calls.append("drainFinished")
                return .accepted(lateReplay: false)
            }
        }

        /// Starts the occupying flush and returns once it is genuinely holding the gate.
        func occupyGate() async -> Task<Void, Never> {
            let task = Task { @MainActor in await self.coordinator.processPendingSyncItems() }
            while release == nil {
                await Task.yield()
            }
            return task
        }

        func releaseGate() {
            release?()
            release = nil
        }
    }

    /// DEFECT 1: awaiting the battery must mean the battery FINISHED. It previously
    /// returned void the instant the gate was busy, so callers chained the achievement
    /// resend onto a drain that had not run — a stale pre-drain snapshot. Cold start hits
    /// this routinely (RootView dispatches the flush and the launch recovery concurrently).
    @Test func aBatteryArrivingMidFlushCompletesBeforeItsAwaitReturns() async {
        let queue = RecordingQueue()
        let holder = GateHolder(queue: queue)
        queue.nonTerminalSessionIds = [UUID().uuidString]
        let occupying = await holder.occupyGate()

        var batteryFinished = false
        let battery = Task { @MainActor in
            await holder.coordinator.resumeGameplaySyncAfterChildConsent()
            batteryFinished = true
        }

        // While the first flush holds the gate, none of the battery may have run...
        await Task.yield()
        #expect(!queue.calls.contains("resetBudget"))
        #expect(!batteryFinished)

        holder.releaseGate()
        _ = await occupying.value
        _ = await battery.value

        // ...and once the await returns, ALL of it has, in order.
        #expect(batteryFinished)
        #expect(queue.calls.contains("resetBudget"))
        #expect(queue.calls.contains("publish"))
        let budgetIndex = queue.calls.firstIndex(of: "resetBudget")!
        let publishIndex = queue.calls.firstIndex(of: "publish")!
        let drainDoneIndex = queue.calls.firstIndex(of: "drainFinished")!
        // The occupying drain finished first; then the whole battery ran in order.
        #expect(drainDoneIndex < budgetIndex)
        #expect(budgetIndex < publishIndex)
    }

    /// DEFECT 2: a battery parked at hard sign-out must never run against the NEXT
    /// account — an adult inherits a child's recovery otherwise.
    @Test func aBatteryParkedAtPurgeNeverRunsForTheNextAccount() async {
        let queue = RecordingQueue()
        let holder = GateHolder(queue: queue)
        queue.nonTerminalSessionIds = [UUID().uuidString]
        let occupying = await holder.occupyGate()

        var batteryUnwound = false
        _ = Task { @MainActor in
            await holder.coordinator.resumeGameplaySyncAfterChildConsent()
            batteryUnwound = true
        }
        await Task.yield()

        // Hard sign-out while the battery is parked, then the next account signs in.
        holder.coordinator.suspendProcessingForPurge()

        // The purge must WAKE the parked battery so it unwinds. Polled with a bound rather
        // than awaited, so a regression that leaves it suspended forever fails this test
        // instead of wedging the suite.
        for _ in 0..<200 where !batteryUnwound {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(batteryUnwound, "a battery parked at purge must unwind, not wait forever")
        guard batteryUnwound else {
            // Regression: the battery is still suspended and would run against the next
            // account. Stop here rather than driving the leaked state further, so this
            // fails cleanly instead of wedging.
            holder.releaseGate()
            return
        }

        holder.coordinator.resumeProcessingAfterPurge()

        holder.releaseGate()
        _ = await occupying.value

        #expect(!queue.calls.contains("resetBudget"))
        #expect(!queue.calls.contains("readCancelled"))
        #expect(!queue.calls.contains("publish"))

        // The gate must be free — the bailing battery never claimed it.
        queue.calls = []
        await holder.coordinator.processPendingSyncItems()
        #expect(queue.calls.contains("fetchPending"))
    }

    /// R3: the universal admission path is untouched — it clears the backoff (never the
    /// budget), publishes nothing, and drains. This is the behaviour that shipped with
    /// FR-28c for every join, and adults must keep getting exactly it.
    @Test func theUniversalResumeStillOnlyClearsBackoffAndDrains() async {
        let queue = RecordingQueue()
        queue.nonTerminalSessionIds = [UUID().uuidString]
        let coordinator = SyncCoordinator(repository: queue)
        var publishCount = 0
        coordinator.setCanonicalSessionPublisher { _ in publishCount += 1 }

        await coordinator.resumeGameplaySyncAfterConsent()

        #expect(publishCount == 0)
        #expect(queue.calls.contains("clearBackoff"))
        #expect(!queue.calls.contains("resetBudget"))
        #expect(!queue.calls.contains("readCancelled"))
        #expect(queue.calls.contains("fetchPending"))
    }
}

// MARK: - R4. The drain's failure classification, pinned end to end

@MainActor
struct GameplayDrainFailureClassificationTests {

    private func queueWithOneGameplayRow(
        _ queue: ConsentResumePublishBeforeDrainTests.RecordingQueue,
        id: String,
        sessionId: UUID,
        eventId: String
    ) {
        queue.pending = [
            SyncQueueItem(
                id: id,
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: sessionId.uuidString,
                payloadEventId: eventId
            )
        ]
    }

    /// The FR-28 classification the whole fix rests on, pinned at the drain level:
    /// reverting `markHeld` to `markFailed` fails this test.
    @Test func anUnconsentedChildRejectionHoldsTheRowAndSpendsNothing() async {
        let queue = ConsentResumePublishBeforeDrainTests.RecordingQueue()
        let sessionId = UUID()
        queueWithOneGameplayRow(queue, id: "row-1", sessionId: sessionId, eventId: "evt-1")

        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setGameplayEventAppender { _ in throw childRestrictionError() }

        await coordinator.processPendingSyncItems()

        #expect(queue.calls.contains("markHeld"))
        #expect(!queue.calls.contains("markFailed"))
        #expect(queue.states["row-1"] == .failed)
        // The budget is the whole point: a hold must leave it untouched.
        #expect(queue.attemptCounts["row-1"] == nil)
    }

    /// R1a: a genuine server verdict is terminal and must NOT land in `cancelled`, or
    /// consent recovery would resurrect data the server deliberately refused.
    @Test func aPermanentServerRejectionLandsInRejectedNotCancelled() async {
        let queue = ConsentResumePublishBeforeDrainTests.RecordingQueue()
        let sessionId = UUID()
        queueWithOneGameplayRow(queue, id: "row-1", sessionId: sessionId, eventId: "evt-1")

        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionRemoved)
        }
        // A non-child failed-precondition — e.g. "discovery not found for removal".
        coordinator.setGameplayEventAppender { _ in
            throw NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.failedPrecondition.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "discovery not found for removal"]
            )
        }

        await coordinator.processPendingSyncItems()

        #expect(queue.states["row-1"] == .rejected)
        #expect(!queue.calls.contains("markCancelled"))
    }

    /// An invalid-argument verdict is equally terminal.
    @Test func anInvalidArgumentRejectionIsTerminalToo() async {
        let queue = ConsentResumePublishBeforeDrainTests.RecordingQueue()
        let sessionId = UUID()
        queueWithOneGameplayRow(queue, id: "row-1", sessionId: sessionId, eventId: "evt-1")

        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setGameplayEventAppender { _ in
            throw NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.invalidArgument.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "bad payload"]
            )
        }

        await coordinator.processPendingSyncItems()

        #expect(queue.states["row-1"] == .rejected)
    }

    /// A malformed row can never be recovered either.
    @Test func aMalformedRowIsRejectedNotCancelled() async {
        let queue = ConsentResumePublishBeforeDrainTests.RecordingQueue()
        queue.pending = [
            SyncQueueItem(
                id: "row-bad",
                kind: .gameplayEvent,
                state: .pending,
                attemptCount: 0,
                createdAt: .now,
                updatedAt: .now,
                payloadSessionId: "not-a-uuid",
                payloadEventId: "evt-1"
            )
        ]
        let coordinator = SyncCoordinator(repository: queue)

        await coordinator.processPendingSyncItems()

        #expect(queue.states["row-bad"] == .rejected)
        #expect(!queue.calls.contains("markCancelled"))
    }

    /// A genuine transient failure still spends the budget — the hold exemption must not
    /// disable give-up progress generally.
    @Test func aTransientFailureStillSpendsTheBudget() async {
        let queue = ConsentResumePublishBeforeDrainTests.RecordingQueue()
        let sessionId = UUID()
        queueWithOneGameplayRow(queue, id: "row-1", sessionId: sessionId, eventId: "evt-1")

        let coordinator = SyncCoordinator(repository: queue)
        coordinator.setLocalGameplayEventProvider { eventId in
            TripActivityEvent(id: eventId, sessionId: sessionId, kind: .regionFound)
        }
        coordinator.setGameplayEventAppender { _ in throw TransientError() }

        await coordinator.processPendingSyncItems()

        #expect(queue.calls.contains("markFailed"))
        #expect(queue.attemptCounts["row-1"] == 1)
    }
}

// MARK: - A. Pre-emptive restricted holds in the XP / achievement services

@MainActor
struct RestrictedSessionPreemptiveHoldTests {

    private func makeUser() -> AppUser {
        AppUser(id: "u-1", userName: "kid", firebaseUID: "uid-1")
    }

    private var entitlement: EntitlementState { EntitlementService.shared.entitlementState(for: makeUser()) }

    // --- Achievements ---

    /// While restricted the callable is never even attempted, and the batch is remembered
    /// rather than discarded.
    @Test func achievementSyncDoesNotCallWhileRestricted() async {
        var callCount = 0
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { true }
        )

        let attempt = await service.syncUnlocks(
            user: makeUser(),
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 3)]
        )

        #expect(callCount == 0)
        #expect(attempt == .heldForChildRestriction)
    }

    /// The cap used to be spent by refusals. Many restricted retries must leave it intact,
    /// so the batch is still alive when consent arrives.
    @Test func restrictedRetriesNeverExhaustTheAchievementCap() async {
        var callCount = 0
        var restricted = true
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { restricted }
        )
        let user = makeUser()

        await service.syncUnlocks(
            user: user,
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 3)]
        )
        for _ in 0..<20 {
            await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }
        #expect(callCount == 0)

        // Consent: the very next retry must reach the server with the batch intact.
        restricted = false
        await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        #expect(callCount == 1)
    }

    /// A rejection that races the pre-emptive check is classified as a hold and refunded,
    /// so the budget still survives.
    @Test func aRacingAchievementRejectionIsHeldNotSpent() async {
        var callCount = 0
        var restricted = false
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in
                callCount += 1
                throw childRestrictionError()
            },
            isRestrictedUnconsentedChild: { restricted }
        )
        let user = makeUser()

        await service.syncUnlocks(
            user: user,
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 3)]
        )
        for _ in 0..<10 {
            await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }
        // Every one of those was a hold, so the batch is still pending. Prove it by
        // letting the next call succeed.
        restricted = false
        callCount = 0
        let succeeding = AchievementUnlockSyncService(
            remoteCall: { _ in callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { false }
        )
        await succeeding.syncUnlocks(
            user: user,
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 3)]
        )
        #expect(callCount == 1)
    }

    /// A genuine failure still counts down and is eventually given up on — the hold
    /// exemption must not disable the cap entirely.
    @Test func genuineAchievementFailuresStillExhaustTheCap() async {
        var callCount = 0
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in
                callCount += 1
                throw TransientError()
            },
            isRestrictedUnconsentedChild: { false }
        )
        let user = makeUser()

        await service.syncUnlocks(
            user: user,
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 3)]
        )
        for _ in 0..<10 {
            await service.retryPendingIfNeeded(user: user, entitlement: entitlement)
        }

        // 1 initial + 3 retries, then the batch is dropped and retries stop calling.
        #expect(callCount == 4)
    }

    /// C.2: the durable second chance. Re-sending the full local unlock set does not
    /// depend on the volatile pending batch surviving a restart.
    @Test func recoveryResendsEveryLocallyUnlockedAchievement() async {
        var sentIds: [[String]] = []
        let service = AchievementUnlockSyncService(
            remoteCall: { payload in
                let candidates = (payload["candidates"] as? [[String: Any]]) ?? []
                sentIds.append(candidates.compactMap { $0["achievementId"] as? String }.sorted())
                return [:]
            },
            isRestrictedUnconsentedChild: { false }
        )
        let candidates = [
            AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 5),
            AchievementUnlockSyncCandidate(achievementId: "a-2", lastProgress: 9)
        ]

        await service.resendAllLocallyUnlockedAchievements(user: makeUser(), entitlement: entitlement, candidates: candidates)
        await service.resendAllLocallyUnlockedAchievements(user: makeUser(), entitlement: entitlement, candidates: candidates)

        // Idempotent by repetition: the server dedupes via alreadySyncedIds, so the same
        // full set every time is the correct, safe payload.
        #expect(sentIds == [["a-1", "a-2"], ["a-1", "a-2"]])
    }

    @Test func recoveryResendIsHeldWhileRestricted() async {
        var callCount = 0
        let service = AchievementUnlockSyncService(
            remoteCall: { _ in callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { true }
        )

        await service.resendAllLocallyUnlockedAchievements(
            user: makeUser(),
            entitlement: entitlement,
            candidates: [AchievementUnlockSyncCandidate(achievementId: "a-1", lastProgress: 5)]
        )

        #expect(callCount == 0)
    }

    /// R2b: the server hard-rejects more than 20 candidates per call with
    /// `invalid-argument`, and it counts the RAW array before deduping. The recovery
    /// chunk size must therefore never exceed 20.
    @Test func theResendChunkSizeRespectsTheServerCap() {
        #expect(ConsentRecoverySupport.maxAchievementCandidatesPerCall <= 20)
        #expect(ConsentRecoverySupport.maxAchievementCandidatesPerCall > 0)
    }

    /// R7: a network drop right after the consent edge must not spend real retry budget.
    @Test func kicksAreSkippedOfflineAndWithoutAnIdentity() {
        #expect(ConsentRecoveryKickPolicy.shouldKick(userId: "uid-1", isOnline: true))
        #expect(!ConsentRecoveryKickPolicy.shouldKick(userId: "uid-1", isOnline: false))
        #expect(!ConsentRecoveryKickPolicy.shouldKick(userId: "", isOnline: true))
    }

    // --- Return streak ---

    @Test func streakClaimDoesNotCallWhileRestricted() async {
        var callCount = 0
        let service = ReturnStreakDailyXpClaimService(
            remoteCall: { _ in callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { true }
        )

        await service.claimIfNeeded(userId: "uid-1", dayKey: "2026-08-13", currentStreak: 4)

        #expect(callCount == 0)
    }

    /// The day survives the whole restricted period and is claimed at consent — the
    /// server accepts a past `dayKey` and dedupes by it.
    @Test func theHeldDayIsClaimedAtConsentWithItsOriginalStreak() async {
        var claimed: [(String, Int)] = []
        var restricted = true
        let service = ReturnStreakDailyXpClaimService(
            remoteCall: { payload in
                claimed.append((payload["dayKey"] as? String ?? "", payload["currentStreak"] as? Int ?? 0))
                return ["granted": true, "alreadyClaimed": false]
            },
            isRestrictedUnconsentedChild: { restricted }
        )

        await service.claimIfNeeded(userId: "uid-1", dayKey: "2026-08-10", currentStreak: 7)
        for _ in 0..<20 {
            await service.retryPendingIfNeeded(userId: "uid-1")
        }
        #expect(claimed.isEmpty)

        restricted = false
        service.resetRetryBudgetAfterConsent()
        await service.retryPendingIfNeeded(userId: "uid-1")

        #expect(claimed.count == 1)
        #expect(claimed.first?.0 == "2026-08-10")
        #expect(claimed.first?.1 == 7)
    }

    @Test func aRacingStreakRejectionIsHeldNotSpent() async {
        var callCount = 0
        let service = ReturnStreakDailyXpClaimService(
            remoteCall: { _ in
                callCount += 1
                throw childRestrictionError(reason: "child_account")
            },
            isRestrictedUnconsentedChild: { false }
        )

        await service.claimIfNeeded(userId: "uid-1", dayKey: "2026-08-10", currentStreak: 7)
        for _ in 0..<10 {
            await service.retryPendingIfNeeded(userId: "uid-1")
        }

        // Never capped out: the refund keeps the candidate retryable indefinitely.
        #expect(callCount == 11)
    }

    @Test func genuineStreakFailuresStillExhaustTheCap() async {
        var callCount = 0
        let service = ReturnStreakDailyXpClaimService(
            remoteCall: { _ in
                callCount += 1
                throw TransientError()
            },
            isRestrictedUnconsentedChild: { false }
        )

        await service.claimIfNeeded(userId: "uid-1", dayKey: "2026-08-10", currentStreak: 7)
        for _ in 0..<10 {
            await service.retryPendingIfNeeded(userId: "uid-1")
        }

        #expect(callCount == 4)
    }

    // --- XP grant reconcile ---

    /// Closes the creation-time race: the client refuses to make the call at all, so a
    /// reconcile cannot slip through the ~300ms window before `declareChildRegistration`
    /// has written the flag.
    @Test func xpReconcileDoesNotCallWhileRestricted() async {
        var callCount = 0
        let service = XpGrantReconcileService(
            remoteCall: { callCount += 1; return [:] },
            isRestrictedUnconsentedChild: { true }
        )

        let outcome = await service.reconcileIfNeeded(userId: "uid-1", isOnline: true)

        #expect(callCount == 0)
        #expect(outcome == .skippedChildRestricted)
    }

    /// A restricted skip must not consume the once-per-session guard, or consent would
    /// find the reconcile already "attempted" and never run it.
    @Test func aRestrictedSkipDoesNotConsumeTheOncePerSessionGuard() async {
        var callCount = 0
        var restricted = true
        let service = XpGrantReconcileService(
            remoteCall: { callCount += 1; return ["totalXp": 10] },
            isRestrictedUnconsentedChild: { restricted }
        )

        for _ in 0..<5 {
            _ = await service.reconcileIfNeeded(userId: "uid-1", isOnline: true)
        }
        #expect(callCount == 0)

        restricted = false
        let outcome = await service.reconcileIfNeeded(userId: "uid-1", isOnline: true)

        #expect(callCount == 1)
        if case .reconciled = outcome {} else {
            Issue.record("expected a real reconcile after consent, got \(outcome)")
        }
    }

    @Test func aRacingReconcileRejectionIsHeldAndStaysRetryable() async {
        var callCount = 0
        let service = XpGrantReconcileService(
            remoteCall: {
                callCount += 1
                throw childRestrictionError()
            },
            isRestrictedUnconsentedChild: { false }
        )

        let first = await service.reconcileIfNeeded(userId: "uid-1", isOnline: true)
        let second = await service.reconcileIfNeeded(userId: "uid-1", isOnline: true)

        #expect(first == .skippedChildRestricted)
        #expect(second == .skippedChildRestricted)
        // The guard was released both times, so consent still gets a real attempt.
        #expect(callCount == 2)
    }
}

// MARK: - C. The durable recovery pass and its restricted guard

@MainActor
struct ChildRestrictedDataRecoveryServiceTests {

    @MainActor
    private final class World {
        var restricted = false
        var resolved = true
        var childAccount = true
        private(set) var order: [String] = []
        var gameplayRecoveries: Int { order.filter { $0 == "gameplay" }.count }
        var achievementResends: Int { order.filter { $0 == "achievements" }.count }

        func makeService() -> ChildRestrictedDataRecoveryService {
            ChildRestrictedDataRecoveryService(
                dependencies: .init(
                    isRestrictedUnconsentedChild: { [weak self] in self?.restricted ?? false },
                    isChildAccountSession: { [weak self] in self?.childAccount ?? true },
                    isSessionResolved: { [weak self] in self?.resolved ?? true },
                    recoverAndDrainGameplay: { [weak self] in self?.order.append("gameplay") },
                    resendAllLocallyUnlockedAchievements: { [weak self] in
                        self?.order.append("achievements")
                    }
                )
            )
        }
    }

    /// The guard that matters: recovery while restricted would make cloud calls for a
    /// child without consent and burn the budgets the holds exist to protect.
    @Test func theLaunchPassNeverRunsWhileRestricted() async {
        let world = World()
        world.restricted = true
        let service = world.makeService()

        await service.runLaunchRecoveryIfEligible()

        #expect(world.gameplayRecoveries == 0)
        #expect(world.achievementResends == 0)
    }

    /// R2a: an adult never ran under a restriction, so none of this applies to them —
    /// no extra callables on their cold start.
    @Test func theLaunchPassNeverRunsForAnAdultAccount() async {
        let world = World()
        world.childAccount = false
        let service = world.makeService()

        await service.runLaunchRecoveryIfEligible()

        #expect(world.order.isEmpty)
    }

    @Test func theLaunchPassWaitsForAResolvedSession() async {
        let world = World()
        world.resolved = false
        let service = world.makeService()

        await service.runLaunchRecoveryIfEligible()

        #expect(world.gameplayRecoveries == 0)
    }

    @Test func theLaunchPassRunsOnceForAConsentedChildSession() async {
        let world = World()
        let service = world.makeService()

        await service.runLaunchRecoveryIfEligible()
        await service.runLaunchRecoveryIfEligible()
        await service.runLaunchRecoveryIfEligible()

        #expect(world.gameplayRecoveries == 1)
        #expect(world.achievementResends == 1)
    }

    /// R2c: achievements are re-derived from progression the drain is still settling, so
    /// the resend has to come after it — in both entry points.
    @Test func gameplayDrainsBeforeAchievementsResendInBothPaths() async {
        let launchWorld = World()
        await launchWorld.makeService().runLaunchRecoveryIfEligible()
        #expect(launchWorld.order == ["gameplay", "achievements"])

        let consentWorld = World()
        await consentWorld.makeService().runConsentRecovery()
        #expect(consentWorld.order == ["gameplay", "achievements"])
    }

    /// The async-shaped version of the test above, and the one that would have caught
    /// DEFECT 1: the gameplay step genuinely SUSPENDS, so a `recoverAndDrainGameplay` that
    /// returns before its work is done lets the achievement resend observe pre-drain state.
    /// The synchronous stub above cannot distinguish the two.
    @Test func theAchievementResendObservesPostDrainStateEvenWhenTheDrainSuspends() async {
        var order: [String] = []
        var drainHasFinished = false
        var resendSawFinishedDrain: Bool?
        var releaseDrain: (() -> Void)?

        let service = ChildRestrictedDataRecoveryService(
            dependencies: .init(
                isRestrictedUnconsentedChild: { false },
                isChildAccountSession: { true },
                isSessionResolved: { true },
                recoverAndDrainGameplay: {
                    order.append("gameplay-start")
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        releaseDrain = { c.resume() }
                    }
                    drainHasFinished = true
                    order.append("gameplay-done")
                },
                resendAllLocallyUnlockedAchievements: {
                    resendSawFinishedDrain = drainHasFinished
                    order.append("achievements")
                }
            )
        )

        let run = Task { @MainActor in await service.runConsentRecovery() }
        while releaseDrain == nil {
            await Task.yield()
        }
        // The resend must NOT have run while the drain is still in flight.
        #expect(resendSawFinishedDrain == nil)

        releaseDrain?()
        _ = await run.value

        #expect(order == ["gameplay-start", "gameplay-done", "achievements"])
        #expect(resendSawFinishedDrain == true)
    }

    /// A blocked launch pass must not have consumed its one chance — consent is what
    /// makes it eligible, and it has to run then.
    @Test func aBlockedLaunchPassStaysAvailableForConsent() async {
        let world = World()
        world.restricted = true
        let service = world.makeService()
        await service.runLaunchRecoveryIfEligible()

        world.restricted = false
        await service.runConsentRecovery()

        #expect(world.gameplayRecoveries == 1)
        #expect(world.achievementResends == 1)
    }

    @Test func signOutRestoresTheLaunchPassForTheNextAccount() async {
        let world = World()
        let service = world.makeService()
        await service.runLaunchRecoveryIfEligible()

        service.resetForSignOut()
        await service.runLaunchRecoveryIfEligible()

        #expect(world.gameplayRecoveries == 2)
    }
}
