//
//  SyncCoordinator.swift
//  LicensePlateApp
//
//  Step 06.5 — Queue processing shell and user-profile sync.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

/// Thrown when `appendTripActivityEvent` does not complete within `SyncCoordinator.gameplayAppendRemoteTimeoutNanoseconds` (wedging guard).
private struct GameplayAppendRemoteTimedOutError: Error {}

/// Resolves the upload-versus-timer race exactly once. Both racers hop to the main actor
/// before claiming, so the flag needs no lock.
@MainActor
private final class OneShotResumeGate {
    private var claimed = false
    /// The timer racer, cancelled by a winning upload so it does not sleep out the bound.
    var timer: Task<Void, Never>?

    /// True for the first caller only.
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }
}

@MainActor
protocol SyncCoordinatorProtocol: AnyObject {
    func enqueueForSync(sessionId: UUID, eventId: String) throws
    /// Enqueues a gameplay sync item only when none exists yet for `eventId` in a non-terminal queue state.
    func ensureGameplayEventEnqueued(sessionId: UUID, eventId: String) throws
    func enqueueUserProfileSync(userId: String) throws
    func processPendingSyncItems() async
    /// Debounced flush after gameplay enqueue; no-op when offline (see `setGameplaySyncOnlineProvider`).
    func scheduleDebouncedGameplaySyncFlushIfOnline()
}

@MainActor
final class SyncCoordinator: SyncCoordinatorProtocol {

    static let shared = SyncCoordinator(repository: SyncQueueRepository.shared)

    /// Delay after the last `scheduleDebouncedGameplaySyncFlushIfOnline` before running `processPendingSyncItems` when online.
    static let gameplaySyncDebounceNanoseconds: UInt64 = 650_000_000

    /// Upper bound on a single `appendEventToRemote` await so a hung `httpsCallable` cannot block all later flushes.
    static let gameplayAppendRemoteTimeoutNanoseconds: UInt64 = 45_000_000_000

    /// How long the retry wake-up waits past a parked row's `nextRetryAt` before draining, so the row
    /// reads as due (`fetchFailedRetryDue` filters `nextRetryAt <= now`). Half a second keeps the
    /// transient `game not found` re-drive at exactly the 3.5 s it always used (3 s + 0.5 s).
    private static let gameplayRetryWakeupSlackSeconds: TimeInterval = 0.5

    /// Max retries for transient `game not found` before treating like a permanent sync failure.
    private static let gameplayGameNotFoundMaxAttempts = 10

    /// Cap on the retry wake-up's offline probe interval (§3.1.1 item 31), which doubles from
    /// `gameplayBackoffBaseSeconds` while every probe finds the device offline.
    private static let gameplayOfflineProbeMaxSeconds: TimeInterval = 900

    /// Max extra `fetchPending()` passes per `processPendingSyncItems` so large offline backlogs drain without another user action.
    private static let maxGameplayBacklogDrainPasses = 10

    private let repository: SyncQueueRepositoryProtocol
    private var userSyncExecutor: UserSyncExecutorProtocol?
    private var lastProcessPendingRunAt: Date?
    private let processPendingMinInterval: TimeInterval = 30

    /// Defaults to `false` until `RootView` wires `authService.isOnline`, so tests and early launch do not upload while “offline.”
    private var gameplaySyncOnlineProvider: () -> Bool = { false }
    /// F-6 (FR-28): while true (unconsented child), gameplay uploads hold — queued
    /// events stay pending and resume automatically when consent lifts the hold.
    /// User-profile sync is NOT held (the declared account may sync, FR-27).
    private var gameplayCloudSyncHoldProvider: () -> Bool = { false }
    /// Publishes one session's canonical state. Injectable so the consent-resume ordering
    /// (publish before drain) is testable without Firebase.
    private var canonicalSessionPublisher: (UUID) async -> Void = { sessionId in
        try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
    }
    /// Resolves a local `TripActivityEvent` by id. Injectable so the drain's failure
    /// classification is testable without SwiftData; recovery also uses it to avoid
    /// re-enqueuing an event the device no longer has (e.g. superseded and deleted).
    private var localGameplayEvent: (String) -> TripActivityEvent? = { eventId in
        (try? TripActivityEventRepository.shared.event(byId: eventId)) ?? nil
    }
    /// Uploads one event. Injectable so the drain's FR-28 hold-vs-reject classification is
    /// pinned by tests without Firebase.
    private var gameplayEventAppender: (TripActivityEvent) async throws -> GameplayEventAppendOutcome = { event in
        // The drain's [GameplaySync] verdict is authoritative; this [TripEndSync] line is
        // written when the CALL returns, so after a timeout it can post-date the verdict.
        let traced = event.kind == .tripEnded || event.kind == .gameEnded
        do {
            let outcome = try await TripCanonicalRemoteSyncService.shared.appendEventToRemote(event)
            if traced {
                TripEndSyncDiagnostics.log("upload \(event.kind.rawValue) \(event.id.prefix(8)) for \(event.sessionId.uuidString.prefix(8)) → \(outcome)")
            }
            return outcome
        } catch {
            if traced {
                TripEndSyncDiagnostics.log("upload \(event.kind.rawValue) \(event.id.prefix(8)) for \(event.sessionId.uuidString.prefix(8)) FAILED \(error)")
            }
            throw error
        }
    }
    /// Bound on one upload await (see `withRemoteTimeout`); tests shorten it.
    private var appendRemoteTimeoutNanoseconds: UInt64 = SyncCoordinator.gameplayAppendRemoteTimeoutNanoseconds
    private var gameplayDebouncedFlushTask: Task<Void, Never>?
    private var gameplayFlushInProgress = false
    private var pendingAnotherGameplayFlush = false
    /// A child-consent battery that arrived while the gate was held.
    private var pendingChildConsentResume = false
    /// Batteries suspended waiting for the gate. Resumed by `releaseGameplayFlushGate` (to
    /// re-attempt) or by `suspendProcessingForPurge` (to bail).
    private var childConsentResumeWaiters: [CheckedContinuation<Void, Never>] = []
    private var processingSuspendedForPurge = false
    /// §3.1.1 item 31 — the ONE coalesced wake-up that retries rows parked on a retryable failure
    /// (transient, timeout, membership/App Check, `game not found`) when their backoff ends. Every
    /// other trigger (a new find's debounce, a reachability edge, foreground, launch) is gated on
    /// `gameplaySyncOnlineProvider`, so a monitor stuck at "offline" after the network came back
    /// left a parked find waiting for a relaunch. This one deliberately is not.
    private var gameplayRetryWakeupTask: Task<Void, Never>?
    private var gameplayRetryWakeupDue: Date?
    /// When the wake-up should retry each row it is responsible for — parked by this coordinator on a
    /// retryable failure and not attempted since — by queue row id: the row's `nextRetryAt`, or for a
    /// row parked OFFLINE (due at once, see the drain) the next probe. Lets a drain re-arm the wake-up
    /// for a row whose backoff ends later than the one that just fired, and retire it when none is left.
    /// Kept across a purge suspension: a sign-out that fails leaves these rows with the account.
    private var gameplayRetryParkedDueByItemId: [String: Date] = [:]
    /// Base of the transient / timeout backoff (doubling, capped at 3600 s); membership / App Check
    /// uses half of it (30 s, capped at 900 s); the offline probe starts at it. Tests shorten it.
    private var gameplayBackoffBaseSeconds: TimeInterval = 60
    /// Consecutive drains stopped because the device was offline (§3.1.1 item 31). The next probe is
    /// `gameplayBackoffBaseSeconds` doubled this many times, capped at `gameplayOfflineProbeMaxSeconds`;
    /// any answer from the server resets it.
    private var gameplayOfflineProbeCount = 0

    init(repository: SyncQueueRepositoryProtocol, userSyncExecutor: UserSyncExecutorProtocol? = nil) {
        self.repository = repository
        self.userSyncExecutor = userSyncExecutor
    }

    func setUserSyncExecutor(_ executor: UserSyncExecutorProtocol) {
        userSyncExecutor = executor
    }

    func setGameplaySyncOnlineProvider(_ provider: @escaping () -> Bool) {
        gameplaySyncOnlineProvider = provider
    }

    func setGameplayCloudSyncHoldProvider(_ provider: @escaping () -> Bool) {
        gameplayCloudSyncHoldProvider = provider
    }

    func setCanonicalSessionPublisher(_ publisher: @escaping (UUID) async -> Void) {
        canonicalSessionPublisher = publisher
    }

    func setLocalGameplayEventProvider(_ provider: @escaping (String) -> TripActivityEvent?) {
        localGameplayEvent = provider
    }

    func setGameplayEventAppender(
        _ appender: @escaping (TripActivityEvent) async throws -> GameplayEventAppendOutcome
    ) {
        gameplayEventAppender = appender
    }

    /// Tests shorten the upload bound so a hung appender times out in milliseconds.
    func setGameplayAppendRemoteTimeoutForTesting(nanoseconds: UInt64) {
        appendRemoteTimeoutNanoseconds = nanoseconds
    }

    /// Tests shorten the retry backoff so a parked row's `nextRetryAt` lands in milliseconds (§3.1.1 item 31).
    func setGameplayBackoffBaseSecondsForTesting(_ seconds: TimeInterval) {
        gameplayBackoffBaseSeconds = seconds
    }

    func scheduleDebouncedGameplaySyncFlushIfOnline() {
        guard !processingSuspendedForPurge else {
            GameplaySyncDiagnostics.log("flush.skip reason=suspended trigger=debounce")
            return
        }
        gameplayDebouncedFlushTask?.cancel()
        let debounce = Self.gameplaySyncDebounceNanoseconds
        gameplayDebouncedFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled else { return }
            guard self.gameplaySyncOnlineProvider() else {
                // The one gate the Firestore listeners and the trip callables do NOT share:
                // a device whose reachability reads offline keeps receiving and keeps
                // importing while every one of its own finds waits here (§3.1.1 item 22).
                GameplaySyncDiagnostics.log("flush.skip reason=offline trigger=debounce")
                // §3.1.1 item 31: a find skipped here is never attempted, so it is never parked and
                // no failure arms the wake-up for it. Arm it as a probe: a monitor that is wrong gets
                // the find up within one base interval; a device that really is offline pays one
                // fast -1009, which spends nothing.
                self.scheduleGameplayRetryWakeup(at: Date().addingTimeInterval(self.gameplayBackoffBaseSeconds))
                return
            }
            await self.processPendingSyncItems()
        }
    }

    /// FR-28c consent resume for ANY family admission, child or adult. A child-restriction
    /// hold parks queued rows an hour out; consent retires that reason immediately, so the
    /// backoff must be cleared BEFORE the flush or the backlog sits for the rest of the
    /// hour (`fetchFailedRetryDue()` filters on `nextRetryAt`). Idempotent: with no held
    /// rows this is just an ordinary flush.
    func resumeGameplaySyncAfterConsent() async {
        guard !processingSuspendedForPurge else {
            GameplaySyncDiagnostics.log("flush.skip reason=suspended trigger=consent")
            return
        }
        try? repository.clearGameplayRetryBackoff()
        await processPendingSyncItems()
    }

    /// The full COPPA FR-28 battery, for CHILD accounts only, in the order the failure
    /// modes demand. An adult never accumulates policy holds or restriction-driven
    /// cancels, so running this for them would only erase genuine give-up progress.
    ///
    /// 1. **Retire the cost of the hold** — reset `attemptCount`, so no row arrives at the
    ///    drain part-way to the cancel cap.
    /// 2. **Recover rows already given up on.** Cancelled rows are re-enqueued FIRST, so a
    ///    session whose every row was cancelled becomes visible to step 3 — otherwise
    ///    nothing would ever publish it and its discoveries would stay local forever.
    /// 3. **Publish canonical sessions BEFORE draining.** The child's sessions do not
    ///    exist server-side yet (canonical publish is a no-op while restricted), so a
    ///    drain that runs first meets `game not found` on every event and spends the
    ///    budget racing a publish it could simply have awaited.
    /// 4. **Drain.**
    ///
    /// The whole sequence holds the single-flush gate, so a concurrent scenePhase or
    /// debounced flush cannot start draining between the publishes and the drain.
    ///
    /// Awaiting this means the battery has actually FINISHED. When another flush owns the
    /// gate, this suspends until that flush releases it and then re-attempts the claim,
    /// rather than returning early — callers chain real work on completion (the achievement
    /// resend must observe post-drain progression), so an early return would hand them a
    /// stale snapshot. Cold start makes this the common path: `RootView` dispatches the
    /// launch flush and the launch recovery as concurrent tasks.
    func resumeGameplaySyncAfterChildConsent() async {
        while true {
            if processingSuspendedForPurge {
                GameplaySyncDiagnostics.log("flush.skip reason=suspended trigger=child-consent")
                return
            }
            guard gameplayFlushInProgress else {
                gameplayFlushInProgress = true
                await runChildConsentBatteryHoldingGate()
                return
            }
            // Another flush owns the gate. Park until it releases, then re-attempt —
            // never degrade into a plain flush that would skip recovery and publish.
            pendingChildConsentResume = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                childConsentResumeWaiters.append(continuation)
            }
        }
    }

    private func runChildConsentBatteryHoldingGate() async {
        defer { releaseGameplayFlushGate() }
        try? repository.resetGameplayRetryBudget()
        recoverDroppedGameplayEventRows()
        await publishCanonicalSessionsForQueuedGameplay()
        await processPendingSyncItemsBody()
    }

    /// Re-enqueues gameplay events whose queue row was cancelled and never landed.
    ///
    /// The cancel is not recoverable any other way: canonical replay re-uploads only
    /// `game_started` / `game_ended` / `game_completed`, so a cancelled `region_found` is
    /// a discovery that exists on the device and nowhere else.
    ///
    /// Self-quenching, which is what keeps this bounded: every source row it acts on is
    /// settled to `recovered` in the same pass, so the recoverable set shrinks toward empty
    /// instead of being rescanned on every launch and every family join. Combined with the
    /// repository already excluding events that have a `completed` or `rejected` row, and
    /// with `ensureGameplayEventEnqueued` skipping anything holding a live row, a second
    /// pass re-enqueues nothing and creates no new rows.
    ///
    /// Rows are settled even when they are skipped (event gone locally, or a live row
    /// already exists) — in both cases this row will never be the one that needs healing,
    /// so leaving it `cancelled` would just re-scan it forever.
    /// Returns the number of events re-enqueued.
    @discardableResult
    func recoverDroppedGameplayEventRows() -> Int {
        guard !processingSuspendedForPurge else { return 0 }
        let dropped = (try? repository.unrecoveredCancelledGameplayItems()) ?? []
        guard !dropped.isEmpty else { return 0 }
        var recovered = 0
        var settledIds: [String] = []
        for item in dropped {
            guard let sessionStr = item.payloadSessionId,
                  let sessionId = UUID(uuidString: sessionStr),
                  let eventId = item.payloadEventId else {
                settledIds.append(item.id)
                continue
            }
            guard localGameplayEvent(eventId) != nil else {
                settledIds.append(item.id)
                continue
            }
            do {
                if try repository.hasNonTerminalGameplayItem(forEventId: eventId) {
                    settledIds.append(item.id)
                    continue
                }
                try ensureGameplayEventEnqueued(sessionId: sessionId, eventId: eventId)
                settledIds.append(item.id)
                recovered += 1
            } catch {
                // Leave this row `cancelled` so a later pass can retry the recovery.
                continue
            }
        }
        try? repository.markGameplayItemsRecovered(ids: settledIds)
        return recovered
    }

    /// Publishes the canonical state of every session still referenced by a non-terminal
    /// gameplay row, so `appendTripActivityEvent` has a `games/{id}` to append to.
    private func publishCanonicalSessionsForQueuedGameplay() async {
        let sessionIds = (try? repository.nonTerminalGameplaySessionIds()) ?? []
        for sessionStr in sessionIds {
            guard let sessionId = UUID(uuidString: sessionStr) else { continue }
            await canonicalSessionPublisher(sessionId)
        }
    }

    /// Cancels in-flight debounce and blocks queue processing during hard sign-out wipe.
    ///
    /// A parked child-consent battery MUST be discarded here, not carried across the wipe.
    /// It is bound to the account that earned it, so surviving the purge would run a
    /// child's recovery — budget resets, cancelled-row re-enqueues, canonical publishes —
    /// against whoever signs in next, including an adult who is exempt by design. The
    /// waiters are resumed so their tasks unwind instead of leaking; each re-checks
    /// `processingSuspendedForPurge` on wake and returns without claiming the gate.
    func suspendProcessingForPurge() {
        GameplaySyncDiagnostics.log("queue suspended for purge")
        processingSuspendedForPurge = true
        gameplayDebouncedFlushTask?.cancel()
        gameplayDebouncedFlushTask = nil
        // The wake-up must not drain mid-wipe. Its parked rows stay registered: a sign-out that fails
        // keeps them with the account, and `resumeProcessingAfterPurge` re-arms for them; after a
        // wipe that succeeded the re-armed drain finds nothing and the drain-end filter drops them.
        cancelGameplayRetryWakeup()
        pendingAnotherGameplayFlush = false
        pendingChildConsentResume = false
        let waiters = childConsentResumeWaiters
        childConsentResumeWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func resumeProcessingAfterPurge() {
        let wasSuspended = processingSuspendedForPurge
        if wasSuspended {
            GameplaySyncDiagnostics.log("queue resumed after purge")
        }
        processingSuspendedForPurge = false
        // §3.1.1 item 31: the suspension cancelled the retry wake-up.
        if wasSuspended, let nextDue = gameplayRetryParkedDueByItemId.values.min() {
            scheduleGameplayRetryWakeup(at: nextDue)
        }
    }

    func enqueueForSync(sessionId: UUID, eventId: String) throws {
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .gameplayEvent,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now,
            nextRetryAt: nil,
            payloadSessionId: sessionId.uuidString,
            payloadEventId: eventId,
            payloadData: nil
        )
        try repository.enqueue(item)
    }

    func ensureGameplayEventEnqueued(sessionId: UUID, eventId: String) throws {
        if try repository.hasNonTerminalGameplayItem(forEventId: eventId) {
            return
        }
        try enqueueForSync(sessionId: sessionId, eventId: eventId)
    }

    func enqueueUserProfileSync(userId: String) throws {
        let item = SyncQueueItem(
            id: UUID().uuidString,
            kind: .userProfile,
            state: .pending,
            attemptCount: 0,
            createdAt: .now,
            updatedAt: .now,
            nextRetryAt: nil,
            payloadSessionId: nil,
            payloadEventId: nil,
            payloadData: userId.data(using: .utf8)
        )
        try repository.enqueue(item)
    }

    func processPendingSyncItems() async {
        guard !processingSuspendedForPurge else {
            GameplaySyncDiagnostics.log("flush.skip reason=suspended")
            return
        }
        if gameplayFlushInProgress {
            if !pendingAnotherGameplayFlush {
                GameplaySyncDiagnostics.log("flush.skip reason=inflight — coalesced into the running flush")
            }
            pendingAnotherGameplayFlush = true
            return
        }
        gameplayFlushInProgress = true
        defer { releaseGameplayFlushGate() }
        await processPendingSyncItemsBody()
    }

    /// Releases the single-flush gate and services whatever queued up behind it. A parked
    /// child-consent battery wins over a plain flush — it ends in a drain anyway, and
    /// running the plain flush first would drain past the recovery and publish it needs.
    /// The battery is woken rather than re-dispatched, so its original caller's `await`
    /// is what completes.
    private func releaseGameplayFlushGate() {
        gameplayFlushInProgress = false
        let waiters = childConsentResumeWaiters
        childConsentResumeWaiters = []
        pendingChildConsentResume = false
        let needsAnother = pendingAnotherGameplayFlush
        pendingAnotherGameplayFlush = false
        guard waiters.isEmpty else {
            // Keep any plain-flush request queued: the battery re-claims the gate, and the
            // request is serviced when IT releases.
            pendingAnotherGameplayFlush = needsAnother
            for waiter in waiters {
                waiter.resume()
            }
            return
        }
        if needsAnother {
            Task { [weak self] in
                await self?.processPendingSyncItems()
            }
        }
    }

    /// §3.1.1 item 31. Records a row just parked on a retryable failure and makes sure the ONE
    /// wake-up fires by its `nextRetryAt` (no user action, no reachability edge required).
    private func parkForRetryWakeup(itemId: String, until due: Date) {
        gameplayRetryParkedDueByItemId[itemId] = due
        scheduleGameplayRetryWakeup(at: due)
    }

    /// Coalesced: an already-scheduled wake-up that is due no later than `due` covers this row too;
    /// an earlier `due` cancels and reschedules it. When it fires it drains WITHOUT consulting
    /// `gameplaySyncOnlineProvider` — the drain itself never checks it, and a truly offline attempt
    /// fails fast (-1009), spends no row's budget and stops the drain, doubling only the probe
    /// interval toward 900 s — so a monitor that lies costs one cheap call per probe and never a
    /// parked find.
    private func scheduleGameplayRetryWakeup(at due: Date) {
        if gameplayRetryWakeupTask != nil, let scheduled = gameplayRetryWakeupDue, scheduled <= due {
            return
        }
        gameplayRetryWakeupTask?.cancel()
        gameplayRetryWakeupDue = due
        let delaySeconds = max(due.timeIntervalSinceNow, 0) + Self.gameplayRetryWakeupSlackSeconds
        GameplaySyncDiagnostics.log("retry.wakeup in=\(Int(delaySeconds.rounded(.up)))s")
        gameplayRetryWakeupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.gameplayRetryWakeupTask = nil
            self.gameplayRetryWakeupDue = nil
            GameplaySyncDiagnostics.log("retry.wakeup fired")
            await self.processPendingSyncItems()
        }
    }

    private func cancelGameplayRetryWakeup() {
        gameplayRetryWakeupTask?.cancel()
        gameplayRetryWakeupTask = nil
        gameplayRetryWakeupDue = nil
    }

    private func processPendingSyncItemsBody() async {
        let drainStartedAt = Date()
        var acceptedProgressionSourceEventIds = Set<String>()
        // FR-28: while the unconsented-child hold is on, skip the gameplay drain
        // entirely (queued events simply hold) but still run user-profile sync below.
        let gameplayHeld = gameplayCloudSyncHoldProvider()
        GameplaySyncDiagnostics.log("flush begin held=\(gameplayHeld ? 1 : 0) online=\(gameplaySyncOnlineProvider() ? 1 : 0)")
        var verdictCounts: [String: Int] = [:]
        // One line per queue row, whatever happens to it. `attempts` is the count BEFORE
        // this try. UPPER-CASE labels ended WITHOUT a server acceptance and nothing retries
        // them for an adult; `eligibleIn` = parked until the next trigger, `retryIn` = a
        // wake-up is scheduled. DEBUG-only in full — release builds skip the body.
        func verdict(_ label: String, _ item: SyncQueueItem, _ event: TripActivityEvent?, _ detail: @autoclosure () -> String = "") {
            #if DEBUG
            verdictCounts[label, default: 0] += 1
            let extra = detail()
            GameplaySyncDiagnostics.log(
                "verdict \(label) ev=\(GameplaySyncDiagnostics.short(item.payloadEventId ?? "")) "
                + "kind=\(event?.kind.rawValue ?? "?") sid=\(GameplaySyncDiagnostics.short(item.payloadSessionId ?? "")) "
                + "attempts=\(item.attemptCount)\(extra.isEmpty ? "" : " " + extra)"
            )
            #endif
        }
        var gameplayDrainPass = 0
        gameplayDrain: while !gameplayHeld, gameplayDrainPass < Self.maxGameplayBacklogDrainPasses {
            let pending: [SyncQueueItem]
            do {
                pending = try repository.fetchPending()
            } catch SyncQueueRepositoryError.noModelContext where gameplayDrainPass == 0 {
                // §3.1.1 item 31: a launch flush can run before the queue repository has its
                // ModelContext. That is not an empty queue — the old `try? … ?? []` logged
                // "flush end verdicts=none" and spent the profile-sync throttle on a drain that
                // never read the queue. Any other fetch error keeps the old fallback.
                GameplaySyncDiagnostics.log("flush.skip reason=repository-unconfigured")
                return
            } catch {
                pending = []
            }
            let retryDue = (try? repository.fetchFailedRetryDue()) ?? []
            let candidates = Dictionary(uniqueKeysWithValues: (pending + retryDue).map { ($0.id, $0) }).values.sorted { $0.createdAt < $1.createdAt }

            let gameplayItems = candidates.filter { $0.kind == .gameplayEvent }
            if gameplayItems.isEmpty {
                break
            }
            GameplaySyncDiagnostics.log("drain pass=\(gameplayDrainPass + 1) rows=\(gameplayItems.count) (queue pending=\(pending.count) retryDue=\(retryDue.count))")

            for item in gameplayItems {
                // Attempted now: a re-park below re-registers it with the retry wake-up.
                gameplayRetryParkedDueByItemId[item.id] = nil
                guard let sessionStr = item.payloadSessionId,
                      let eventId = item.payloadEventId,
                      let sessionUUID = UUID(uuidString: sessionStr) else {
                    // Malformed payload: there is nothing to retry and nothing to recover.
                    // `rejected`, not `cancelled`, so consent recovery never picks it up.
                    verdict("REJECTED(malformed)", item, nil)
                    try? repository.markRejected(id: item.id)
                    continue
                }
                do {
                    try repository.markInProgress(id: item.id)
                    guard let event = localGameplayEvent(eventId) else {
                        verdict("completed(no-local-event)", item, nil)
                        try? repository.markCompleted(id: item.id)
                        continue
                    }
                    let outcome = try await Self.withRemoteTimeout(nanoseconds: appendRemoteTimeoutNanoseconds) { [self] in
                        try await self.gameplayEventAppender(event)
                    }
                    // The server answered: the device is online, so the offline probe starts over.
                    gameplayOfflineProbeCount = 0
                    let gameIdStr = event.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                    switch outcome {
                    case .accepted(let lateReplay):
                        verdict("accepted", item, event, "lateReplay=\(lateReplay ? 1 : 0)")
                        if lateReplay {
                            // FR-28h: adopt the server's stamp locally, or this device —
                            // the finder's own — stays the only one computing unfrozen
                            // competitive outcomes.
                            try? TripActivityEventRepository.shared.markGameplayEventLateReplay(id: event.id)
                        }
                        AnalyticsService.shared.log(.gameplayEventServerAccepted(
                            tripSessionId: sessionUUID.uuidString,
                            gameInstanceId: gameIdStr,
                            eventKind: event.kind.rawValue
                        ))
                        if event.kind == .regionFound || event.kind == .gameEnded {
                            acceptedProgressionSourceEventIds.insert(event.id)
                        }
                        if event.kind == .regionFound {
                            GameplayXpSyncSupport.applyResolutionForAcceptedGameplayEvent(event, sessionId: sessionUUID)
                        }
                        if event.kind == .participantLeft {
                            let pid = event.payload?[TripActivityEventPayloadKey.participantId] ?? event.actorId ?? ""
                            if !pid.isEmpty {
                                try? PendingTripLeaveRepository.shared.deletePending(sessionId: sessionUUID, userId: pid)
                                if Auth.auth().currentUser?.uid == pid {
                                    AnalyticsService.shared.log(.tripParticipantLeaveServerCompleted(tripSessionId: sessionUUID.uuidString))
                                }
                            }
                        }
                    case let .superseded(localId, rejection):
                        if event.kind == .regionFound {
                            GameplayXpSyncSupport.applyResolutionForSupersededRegionFound(
                                sessionId: sessionUUID,
                                supersededLocalId: localId,
                                uploadedRegionFound: event,
                                rejection: rejection
                            )
                        }
                        try TripActivityEventRepository.shared.deleteEvent(id: localId)
                        UserProgressionService.shared.handleLocalEventRemoved(id: localId)
                        var imported: [TripActivityEvent] = []
                        if let canonical = CompetitiveSupersedeCanonicalDiscovery.regionFoundEvent(from: rejection) {
                            imported.append(canonical)
                        }
                        imported.append(rejection)
                        try TripActivityEventRepository.shared.importEventsIfAbsent(imported)
                        // After the two throwing local writes above, so a row gets ONE verdict:
                        // a local failure falls to the catch and is reported there instead.
                        verdict("superseded", item, event,
                                "reason=\(rejection.payload?[TripActivityEventPayloadKey.rejectionReason] ?? "?")")
                        let tripName = (try? TripSessionRepository.shared.session(byId: sessionUUID))?.name ?? ""
                        if let info = FairnessResolutionInfo(rejection: rejection, sessionId: sessionUUID, tripSessionName: tripName) {
                            TripCanonicalRemoteSyncService.shared.publishFairnessResolution(info)
                        }
                        AnalyticsService.shared.log(.gameplayEventServerSuperseded(
                            tripSessionId: sessionUUID.uuidString,
                            gameInstanceId: gameIdStr,
                            serverRejectionEventId: rejection.id,
                            reason: rejection.payload?[TripActivityEventPayloadKey.rejectionReason] ?? ""
                        ))
                    }
                    try? repository.markCompleted(id: item.id)
                } catch {
                    let resolvedEvent = localGameplayEvent(eventId)
                    let eventKind = resolvedEvent?.kind.rawValue ?? ""
                    let gameIdStr = resolvedEvent?.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                    if ChildRestrictedModeService.isChildRestrictionRejection(error) {
                        // FR-28: unconsented-child rejection is a hold, never a permanent
                        // failure — the event stays queued and resumes on consent. No
                        // analytics here (no child-only events on the child's instance).
                        //
                        // `markHeld`, not `markFailed`: the row's retry budget is shared by
                        // every failure class and is what the `game not found` cap spends
                        // before cancelling a row for good. Charging a policy refusal
                        // against it would let a long-restricted child arrive at consent
                        // with a budget already spent, and the discovery would be dropped
                        // instead of uploaded.
                        verdict("held(child-restricted)", item, resolvedEvent, "eligibleIn=3600s")
                        try? repository.markHeld(id: item.id, nextRetryAt: Date().addingTimeInterval(3600))
                        continue
                    }
                    if Self.isGameNotStartedHold(error) {
                        // Republish so the server sees the started (or ended) lifecycle,
                        // then park WITHOUT spending the budget — nothing is wrong with
                        // this find, our canonical state just has not caught up.
                        Task { @MainActor in
                            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionUUID)
                        }
                        verdict("held(game-not-started)", item, resolvedEvent, "eligibleIn=60s republish=1")
                        try? repository.markHeld(id: item.id, nextRetryAt: Date().addingTimeInterval(60))
                        continue
                    }
                    if Self.isTransientGameNotFoundGameplayFailure(error) {
                        if item.attemptCount < Self.gameplayGameNotFoundMaxAttempts {
                            Task { @MainActor in
                                try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionUUID)
                            }
                            verdict("failed(game-not-found)", item, resolvedEvent, "retryIn=3s republish=1 cap=\(Self.gameplayGameNotFoundMaxAttempts)")
                            // 3 s so `publishFullSession` can create `games/{id}` on Firestore first.
                            let nextRetryAt = Date().addingTimeInterval(3)
                            try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                            parkForRetryWakeup(itemId: item.id, until: nextRetryAt)
                            continue
                        }
                        AnalyticsService.shared.log(.gameplayEventServerRejected(
                            tripSessionId: sessionUUID.uuidString,
                            eventKind: eventKind,
                            errorCode: (error as NSError).code,
                            errorDomain: (error as NSError).domain
                        ))
                        // The retry cap on a TRANSIENT condition — the server never judged
                        // this event, we simply ran out of patience waiting for its game to
                        // exist. This is the sole producer of `cancelled`, and the sole
                        // thing FR-28 consent recovery is allowed to heal.
                        verdict("CANCELLED(game-not-found-cap)", item, resolvedEvent, "msg=\(GameplaySyncDiagnostics.message(error))")
                        try? repository.markCancelled(id: item.id)
                        continue
                    }
                    if Self.isTransientMembershipOrAppCheckGameplayFailure(error) {
                        // Trip may never have published (App Check) or membership missing — republish and retry.
                        Task { @MainActor in
                            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionUUID)
                        }
                        let attempts = max(item.attemptCount, 0) + 1
                        let delaySeconds = min(pow(2.0, Double(attempts - 1)) * (gameplayBackoffBaseSeconds / 2), 900.0)
                        verdict("failed(membership-or-appcheck)", item, resolvedEvent,
                                "retryIn=\(Int(delaySeconds))s republish=1 code=\((error as NSError).code) msg=\(GameplaySyncDiagnostics.message(error))")
                        let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                        try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                        parkForRetryWakeup(itemId: item.id, until: nextRetryAt)
                        continue
                    }
                    if Self.isDeviceOfflineGameplayFailure(error) {
                        // §3.1.1 item 31: the request never left the device. That is a fact about
                        // the DEVICE, not a verdict on this row, so it spends none of the row's
                        // budget (`markHeld`) and leaves it due at once for the next trigger — a
                        // reachability edge, foreground, relaunch — exactly as the rows behind it,
                        // which the drain stops before: each would fail the same way, and a failed
                        // attempt would park it on its own doubling backoff that nothing clears on
                        // reconnect. The wake-up probes on the coordinator's interval instead.
                        let probeSeconds = min(
                            pow(2.0, Double(gameplayOfflineProbeCount)) * gameplayBackoffBaseSeconds,
                            Self.gameplayOfflineProbeMaxSeconds
                        )
                        gameplayOfflineProbeCount += 1
                        verdict("failed(offline)", item, resolvedEvent,
                                "eligibleIn=0s retryIn=\(Int(probeSeconds))s drainStopped=1 domain=\((error as NSError).domain) code=\((error as NSError).code) msg=\(GameplaySyncDiagnostics.message(error))")
                        try? repository.markHeld(id: item.id, nextRetryAt: nil)
                        parkForRetryWakeup(itemId: item.id, until: Date().addingTimeInterval(probeSeconds))
                        break gameplayDrain
                    }
                    // FR-28h replay verdicts are named explicitly so the classification is
                    // deliberate rather than an accident of `failedPrecondition` catch-all.
                    if Self.isPermanentReplayRejection(error) || Self.isPermanentGameplaySyncFailure(error) {
                        AnalyticsService.shared.log(.gameplayEventServerRejected(
                            tripSessionId: sessionUUID.uuidString,
                            eventKind: eventKind,
                            errorCode: (error as NSError).code,
                            errorDomain: (error as NSError).domain
                        ))
                        // A server VERDICT — invalid argument, permission denied, or a
                        // non-child failed-precondition such as a discovery that no longer
                        // exists. Terminal: consent recovery must never push this back.
                        verdict("REJECTED(permanent)", item, resolvedEvent,
                                "domain=\((error as NSError).domain) code=\((error as NSError).code) msg=\(GameplaySyncDiagnostics.message(error))")
                        try? repository.markRejected(id: item.id)
                    } else {
                        if error is GameplayAppendRemoteTimedOutError {
                            let timeoutSec = max(Int(Self.gameplayAppendRemoteTimeoutNanoseconds / 1_000_000_000), 1)
                            AnalyticsService.shared.log(.gameplayEventAppendTimedOut(
                                tripSessionId: sessionUUID.uuidString,
                                gameInstanceId: gameIdStr,
                                eventKind: eventKind,
                                attemptCount: item.attemptCount,
                                timeoutSeconds: timeoutSec
                            ))
                        }
                        let attempts = max(item.attemptCount, 0) + 1
                        let delaySeconds = min(pow(2.0, Double(attempts - 1)) * gameplayBackoffBaseSeconds, 3600.0)
                        verdict(error is GameplayAppendRemoteTimedOutError ? "failed(timeout)" : "failed(transient)", item, resolvedEvent,
                                "retryIn=\(Int(delaySeconds))s domain=\((error as NSError).domain) code=\((error as NSError).code) msg=\(GameplaySyncDiagnostics.message(error))")
                        let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                        try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                        parkForRetryWakeup(itemId: item.id, until: nextRetryAt)
                    }
                }
            }

            gameplayDrainPass += 1
            let moreGameplay = (try? repository.hasPendingOrRetryDueGameplayItems()) ?? false
            if !moreGameplay {
                break
            }
        }

        if gameplayDrainPass >= Self.maxGameplayBacklogDrainPasses,
           (try? repository.hasPendingOrRetryDueGameplayItems()) ?? false {
            pendingAnotherGameplayFlush = true
        }

        let gameplayStillPending = (try? repository.hasPendingOrRetryDueGameplayItems()) ?? true
        GameplaySyncDiagnostics.log(
            "flush end verdicts=" + (verdictCounts.isEmpty ? "none" : verdictCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            + " retryDue=\(gameplayStillPending ? 1 : 0)"
            // Parked rows (failed/held with backoff still running) are NOT retry-due, so a
            // queue that still holds unsent finds reads retryDue=0; this is the honest count.
            + " queuedSessions=\((try? repository.nonTerminalGameplaySessionIds().count) ?? -1)"
        )
        // §3.1.1 item 31: re-arm the wake-up for a row still parked (one whose backoff ends later
        // than the one that just fired, or the offline probe), or retire it when none is left — a
        // debounce probe included, since this drain attempted its find. An entry that was already
        // due when this drain STARTED and is still here was eligible and not attempted — a held
        // drain, the pass cap, an offline stop (whose probe covers it) — so whatever holds it is not
        // the timer's to retry; dropping it is also what stops a held queue from re-firing every
        // 0.5 s. One that fell due DURING the drain (a long drain, a short backoff) is kept and
        // fires at once.
        gameplayRetryParkedDueByItemId = gameplayRetryParkedDueByItemId.filter { $0.value > drainStartedAt }
        if let nextDue = gameplayRetryParkedDueByItemId.values.min() {
            scheduleGameplayRetryWakeup(at: nextDue)
        } else if gameplayRetryWakeupTask != nil {
            GameplaySyncDiagnostics.log("retry.wakeup cleared reason=none-parked")
            cancelGameplayRetryWakeup()
        }
        if !gameplayStillPending, gameplaySyncOnlineProvider() {
            ProgressionXpDriftAfterSyncReporter.shared.scheduleEvaluationAfterSuccessfulGameplayDrain(
                recentlyAcceptedProgressionSourceEventIds: acceptedProgressionSourceEventIds,
                isOnline: { [weak self] in self?.gameplaySyncOnlineProvider() ?? false },
                hasPendingOrRetryDueGameplay: { [weak self] in
                    (try? self?.repository.hasPendingOrRetryDueGameplayItems()) ?? true
                }
            )
        }

        guard let userSyncExecutor else { return }
        let now = Date()
        if let last = lastProcessPendingRunAt, now.timeIntervalSince(last) < processPendingMinInterval {
            return
        }
        lastProcessPendingRunAt = now

        let pendingForProfile = (try? repository.fetchPending()) ?? []
        let retryDueForProfile = (try? repository.fetchFailedRetryDue()) ?? []
        let profileCandidates = Dictionary(uniqueKeysWithValues: (pendingForProfile + retryDueForProfile).map { ($0.id, $0) }).values.sorted { $0.createdAt < $1.createdAt }

        for item in profileCandidates where item.kind == .userProfile {
            guard let userIdData = item.payloadData,
                  let userId = String(data: userIdData, encoding: .utf8),
                  !userId.isEmpty else {
                // Malformed payload — nothing to retry. Terminal.
                try? repository.markRejected(id: item.id)
                continue
            }

            do {
                try repository.markInProgress(id: item.id)
                try await userSyncExecutor.performUserSync(userId: userId)
                try? repository.saveMetadata(RemoteSyncMetadata(key: "user:\(userId)", lastSyncedAt: .now, valueData: nil))
                try? repository.markCompleted(id: item.id)
            } catch {
                let attempts = max(item.attemptCount, 0) + 1
                let delaySeconds = min(pow(2.0, Double(attempts - 1)) * 60.0, 3600.0)
                let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
            }
        }
    }

    /// Bounds one upload await WITHOUT ever awaiting the loser. The task-group form this
    /// replaces drained the group after its timer fired — which meant awaiting the hung
    /// callable — so the "timeout" never returned: `gameplayFlushInProgress` stayed true and
    /// every later flush no-op'd, silently, for the rest of the process (§3.1.1 item 22). A
    /// hung callable now keeps only its own task alive until the SDK gives up; the drain
    /// marks the row failed with backoff and moves on.
    static func withRemoteTimeout<T: Sendable>(
        nanoseconds: UInt64,
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        let gate = OneShotResumeGate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let work = Task { @MainActor in
                let result: Result<T, Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                guard gate.claim() else { return }
                gate.timer?.cancel()
                continuation.resume(with: result)
            }
            gate.timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard gate.claim() else { return }
                work.cancel()
                continuation.resume(throwing: GameplayAppendRemoteTimedOutError())
            }
        }
    }

    private static func isPermanentGameplaySyncFailure(_ error: Error) -> Bool {
        if isTransientMembershipOrAppCheckGameplayFailure(error) {
            return false
        }
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard let code = FunctionsErrorCode(rawValue: ns.code) else { return false }
        switch code {
        case .failedPrecondition, .permissionDenied, .alreadyExists, .notFound, .invalidArgument:
            return true
        default:
            return false
        }
    }

    /// The server still sees this game's lifecycle as `created`.
    ///
    /// FR-28h narrowed this message to the genuine pre-start edge: an ended game now
    /// ACCEPTS an in-window replay, so reaching this means either the game truly has not
    /// started yet, or our canonical publish has not landed the started state. Both clear
    /// on their own, so it is a HOLD — parked without spending the row's retry budget, and
    /// drained by the next flush once the publish catches up. It used to be classified
    /// permanent, which is what destroyed every offline-completed trip's discoveries.
    private static func isGameNotStartedHold(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard let code = FunctionsErrorCode(rawValue: ns.code), code == .failedPrecondition else { return false }
        return ns.localizedDescription.lowercased().contains("game not started")
    }

    /// FR-28h replay verdicts: the find's timestamp is outside the game's played window, or
    /// it arrived past the replay horizon. Both are final server judgements about THIS
    /// event — retrying cannot change either, so they are permanent (`rejected`), never
    /// recovered.
    private static func isPermanentReplayRejection(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard let code = FunctionsErrorCode(rawValue: ns.code), code == .failedPrecondition else { return false }
        let message = ns.localizedDescription.lowercased()
        return message.contains("replay outside game window") || message.contains("replay horizon expired")
    }

    /// `appendTripActivityEvent` before `games/{id}` exists (publish still in flight or failed). Retry, do not cancel the queue row.
    private static func isTransientGameNotFoundGameplayFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard let code = FunctionsErrorCode(rawValue: ns.code), code == .failedPrecondition else { return false }
        return ns.localizedDescription.lowercased().contains("game not found")
    }

    /// §3.1.1 item 31. `NSURLErrorNotConnectedToInternet` (-1009) / `NSURLErrorDataNotAllowed` (-1020),
    /// directly or as the underlying error: the request never left the device, so the server judged
    /// nothing. Any other network error (a timeout, a dropped connection) may have reached it.
    private static func isDeviceOfflineGameplayFailure(_ error: Error) -> Bool {
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed]
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, offlineCodes.contains(ns.code) { return true }
        guard let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return underlying.domain == NSURLErrorDomain && offlineCodes.contains(underlying.code)
    }

    /// App Check rejection or missing trip membership after a silently failed publish — keep retrying.
    private static func isTransientMembershipOrAppCheckGameplayFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        let message = ns.localizedDescription.lowercased()
        if message.contains("app check") || message.contains("appcheck") {
            return true
        }
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard let code = FunctionsErrorCode(rawValue: ns.code) else { return false }
        switch code {
        case .unauthenticated:
            // enforceAppCheck rejects with unauthenticated when the App Check JWT is missing/invalid.
            return true
        case .permissionDenied:
            return message.contains("not a member") || message.contains("not a trip")
        default:
            return false
        }
    }

}
