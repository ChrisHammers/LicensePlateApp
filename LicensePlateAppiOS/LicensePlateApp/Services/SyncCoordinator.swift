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

private enum GameplayAppendRaceFirst {
    case done(Result<GameplayEventAppendOutcome, Error>)
    case timedOut
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

    /// After transient `game not found`, wait before flushing so `publishFullSession` can create `games/{id}` on Firestore.
    private static let gameplayGameNotFoundRetryDelayNanoseconds: UInt64 = 3_500_000_000

    /// Max retries for transient `game not found` before treating like a permanent sync failure.
    private static let gameplayGameNotFoundMaxAttempts = 10

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
        try await SyncCoordinator.appendEventToRemoteRespectingTimeout(event: event)
    }
    private var gameplayDebouncedFlushTask: Task<Void, Never>?
    private var gameplayFlushInProgress = false
    private var pendingAnotherGameplayFlush = false
    /// A child-consent battery that arrived while the gate was held.
    private var pendingChildConsentResume = false
    /// Batteries suspended waiting for the gate. Resumed by `releaseGameplayFlushGate` (to
    /// re-attempt) or by `suspendProcessingForPurge` (to bail).
    private var childConsentResumeWaiters: [CheckedContinuation<Void, Never>] = []
    private var processingSuspendedForPurge = false

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

    func scheduleDebouncedGameplaySyncFlushIfOnline() {
        guard !processingSuspendedForPurge else { return }
        gameplayDebouncedFlushTask?.cancel()
        let debounce = Self.gameplaySyncDebounceNanoseconds
        gameplayDebouncedFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled else { return }
            guard self.gameplaySyncOnlineProvider() else { return }
            await self.processPendingSyncItems()
        }
    }

    /// FR-28c consent resume for ANY family admission, child or adult. A child-restriction
    /// hold parks queued rows an hour out; consent retires that reason immediately, so the
    /// backoff must be cleared BEFORE the flush or the backlog sits for the rest of the
    /// hour (`fetchFailedRetryDue()` filters on `nextRetryAt`). Idempotent: with no held
    /// rows this is just an ordinary flush.
    func resumeGameplaySyncAfterConsent() async {
        guard !processingSuspendedForPurge else { return }
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
            if processingSuspendedForPurge { return }
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
        processingSuspendedForPurge = true
        gameplayDebouncedFlushTask?.cancel()
        gameplayDebouncedFlushTask = nil
        pendingAnotherGameplayFlush = false
        pendingChildConsentResume = false
        let waiters = childConsentResumeWaiters
        childConsentResumeWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func resumeProcessingAfterPurge() {
        processingSuspendedForPurge = false
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
        guard !processingSuspendedForPurge else { return }
        if gameplayFlushInProgress {
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

    /// Wakes the queue after `nextRetryAt` for transient `game not found` (no user action required).
    private func scheduleProcessPendingAfterGameplayRetryDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.gameplayGameNotFoundRetryDelayNanoseconds)
            await self?.processPendingSyncItems()
        }
    }

    private func processPendingSyncItemsBody() async {
        var acceptedProgressionSourceEventIds = Set<String>()
        // FR-28: while the unconsented-child hold is on, skip the gameplay drain
        // entirely (queued events simply hold) but still run user-profile sync below.
        let gameplayHeld = gameplayCloudSyncHoldProvider()
        var gameplayDrainPass = 0
        while !gameplayHeld, gameplayDrainPass < Self.maxGameplayBacklogDrainPasses {
            let pending = (try? repository.fetchPending()) ?? []
            let retryDue = (try? repository.fetchFailedRetryDue()) ?? []
            let candidates = Dictionary(uniqueKeysWithValues: (pending + retryDue).map { ($0.id, $0) }).values.sorted { $0.createdAt < $1.createdAt }

            let gameplayItems = candidates.filter { $0.kind == .gameplayEvent }
            if gameplayItems.isEmpty {
                break
            }

            for item in gameplayItems {
                guard let sessionStr = item.payloadSessionId,
                      let eventId = item.payloadEventId,
                      let sessionUUID = UUID(uuidString: sessionStr) else {
                    // Malformed payload: there is nothing to retry and nothing to recover.
                    // `rejected`, not `cancelled`, so consent recovery never picks it up.
                    try? repository.markRejected(id: item.id)
                    continue
                }
                do {
                    try repository.markInProgress(id: item.id)
                    guard let event = localGameplayEvent(eventId) else {
                        try? repository.markCompleted(id: item.id)
                        continue
                    }
                    let outcome = try await gameplayEventAppender(event)
                    let gameIdStr = event.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                    switch outcome {
                    case .accepted(let lateReplay):
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
                        try? repository.markHeld(id: item.id, nextRetryAt: Date().addingTimeInterval(60))
                        continue
                    }
                    if Self.isTransientGameNotFoundGameplayFailure(error) {
                        if item.attemptCount < Self.gameplayGameNotFoundMaxAttempts {
                            Task { @MainActor in
                                try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionUUID)
                            }
                            let nextRetryAt = Date().addingTimeInterval(3)
                            try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                            scheduleProcessPendingAfterGameplayRetryDelay()
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
                        try? repository.markCancelled(id: item.id)
                        continue
                    }
                    if Self.isTransientMembershipOrAppCheckGameplayFailure(error) {
                        // Trip may never have published (App Check) or membership missing — republish and retry.
                        Task { @MainActor in
                            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionUUID)
                        }
                        let attempts = max(item.attemptCount, 0) + 1
                        let delaySeconds = min(pow(2.0, Double(attempts - 1)) * 30.0, 900.0)
                        let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                        try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                        continue
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
                        let delaySeconds = min(pow(2.0, Double(attempts - 1)) * 60.0, 3600.0)
                        let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                        try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
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

    private static func appendEventToRemoteRespectingTimeout(event: TripActivityEvent) async throws -> GameplayEventAppendOutcome {
        try await withThrowingTaskGroup(of: GameplayAppendRaceFirst.self) { group in
            group.addTask {
                do {
                    let outcome = try await TripCanonicalRemoteSyncService.shared.appendEventToRemote(event)
                    return .done(.success(outcome))
                } catch {
                    return .done(.failure(error))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.gameplayAppendRemoteTimeoutNanoseconds)
                return .timedOut
            }
            guard let first = try await group.next() else {
                throw GameplayAppendRemoteTimedOutError()
            }
            group.cancelAll()
            while (try? await group.next()) != nil {}
            switch first {
            case .timedOut:
                throw GameplayAppendRemoteTimedOutError()
            case .done(.success(let outcome)):
                return outcome
            case .done(.failure(let error)):
                throw error
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
