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
    /// Records a real delivery attempt that failed: parks the row and SPENDS one unit of
    /// its retry budget (`attemptCount += 1`).
    func markFailed(id: String, nextRetryAt: Date?) throws
    /// Parks a row without spending its retry budget — for POLICY holds, where nothing was
    /// wrong with the row and no progress toward "give up" was made. COPPA FR-28's
    /// unconsented-child rejection is the case: the upload is refused for as long as the
    /// restriction lasts, so counting those refusals as attempts would retire the row's
    /// budget purely for being a child, and the discovery would be dropped at the cap
    /// (`SyncCoordinator.gameplayGameNotFoundMaxAttempts`) instead of uploading at consent.
    func markHeld(id: String, nextRetryAt: Date?) throws
    /// Gave up WITHOUT a server verdict (the transient `game not found` retry cap). The
    /// only state COPPA FR-28 consent recovery re-enqueues.
    func markCancelled(id: String) throws
    /// Terminal: the server issued a final verdict, or the payload was malformed. Recovery
    /// must never resurrect these — re-uploading would push back data the server
    /// deliberately refused or deleted.
    func markRejected(id: String) throws
    func metadata(key: String) throws -> RemoteSyncMetadata?
    func saveMetadata(_ metadata: RemoteSyncMetadata) throws
    /// True if a gameplay sync row exists for this activity event id in pending, inProgress, or failed (retry) state.
    func hasNonTerminalGameplayItem(forEventId eventId: String) throws -> Bool
    /// True if any gameplay row is still `pending`, or `failed` with retry due (used to chain backlog drain passes).
    func hasPendingOrRetryDueGameplayItems() throws -> Bool
    /// After cold start / kill during upload, rows can be stuck `inProgress` and never match `fetchPending`. Clears them to `pending`.
    func resetStuckInProgressSyncItemsToPending() throws
    /// Clears `nextRetryAt` on failed gameplay rows so the next flush picks them up
    /// immediately. Used when the reason they were held has demonstrably gone away —
    /// COPPA FR-28 consent, which retires an hour-long child-restriction backoff.
    /// Returns the number of rows unblocked.
    ///
    /// Runs for EVERY family admission, child or adult (FR-28c shipped semantics).
    @discardableResult
    func clearGameplayRetryBackoff() throws -> Int
    /// Everything `clearGameplayRetryBackoff` does, plus resetting `attemptCount` to 0.
    ///
    /// Child-account consent only. `attemptCount` is one counter shared by every failure
    /// class, and it is what the `game not found` cap spends before cancelling a row for
    /// good — so a child who spent attempts while restricted would otherwise reach the
    /// drain already close to the cap and lose the discovery. An adult never accumulates
    /// policy-hold attempts, so widening this to everyone would only erase genuine
    /// give-up progress.
    /// Returns the number of rows changed.
    @discardableResult
    func resetGameplayRetryBudget() throws -> Int
    /// Gameplay rows in `cancelled` — gave up with no server verdict — for which the same
    /// event id has no `completed` row (it already landed) and no `rejected` row (the
    /// server refused it for good). The durable input to consent recovery.
    ///
    /// Cancelled rows are the precise record of a locally-originated event that was meant
    /// to sync and did not: they carry the session and event ids, and only
    /// `TripActivityEventRecordingService.recordForSync` ever creates them, so a
    /// server-imported peer event can never appear here.
    func unrecoveredCancelledGameplayItems() throws -> [SyncQueueItem]
    /// Settles rows that recovery has just re-enqueued onto a new row, so the recoverable
    /// set shrinks to empty instead of being re-scanned every launch and every join.
    /// This is what makes the pass self-quenching without any device-side flag.
    func markGameplayItemsRecovered(ids: [String]) throws
    /// Distinct `payloadSessionId`s of gameplay rows still in a non-terminal state
    /// (pending / inProgress / failed), oldest row first. These are the sessions whose
    /// canonical state must exist server-side before the queue drains.
    func nonTerminalGameplaySessionIds() throws -> [String]
}

extension SyncQueueRepositoryProtocol {
    /// Pending sync rows ordered by `createdAt`, at most ``SyncQueueRepositoryBatching/defaultPendingFetchLimit``.
    func fetchPending() throws -> [SyncQueueItem] {
        try fetchPending(limit: SyncQueueRepositoryBatching.defaultPendingFetchLimit)
    }
}
