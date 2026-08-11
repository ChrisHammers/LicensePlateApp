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
    private var gameplayDebouncedFlushTask: Task<Void, Never>?
    private var gameplayFlushInProgress = false
    private var pendingAnotherGameplayFlush = false
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

    /// Cancels in-flight debounce and blocks queue processing during hard sign-out wipe.
    func suspendProcessingForPurge() {
        processingSuspendedForPurge = true
        gameplayDebouncedFlushTask?.cancel()
        gameplayDebouncedFlushTask = nil
        pendingAnotherGameplayFlush = false
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
        defer {
            gameplayFlushInProgress = false
            let needsAnother = pendingAnotherGameplayFlush
            pendingAnotherGameplayFlush = false
            if needsAnother {
                Task { [weak self] in
                    await self?.processPendingSyncItems()
                }
            }
        }
        await processPendingSyncItemsBody()
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
                    try? repository.markCancelled(id: item.id)
                    continue
                }
                do {
                    try repository.markInProgress(id: item.id)
                    guard let event = try TripActivityEventRepository.shared.event(byId: eventId) else {
                        try? repository.markCompleted(id: item.id)
                        continue
                    }
                    let outcome = try await Self.appendEventToRemoteRespectingTimeout(event: event)
                    let gameIdStr = event.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                    switch outcome {
                    case .accepted:
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
                    let resolvedEvent = try? TripActivityEventRepository.shared.event(byId: eventId)
                    let eventKind = resolvedEvent?.kind.rawValue ?? ""
                    let gameIdStr = resolvedEvent?.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                    if ChildRestrictedModeService.isChildRestrictionRejection(error) {
                        // FR-28: unconsented-child rejection is a hold, never a permanent
                        // failure — the event stays queued and resumes on consent. No
                        // analytics here (no child-only events on the child's instance).
                        try? repository.markFailed(id: item.id, nextRetryAt: Date().addingTimeInterval(3600))
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
                    if Self.isPermanentGameplaySyncFailure(error) {
                        AnalyticsService.shared.log(.gameplayEventServerRejected(
                            tripSessionId: sessionUUID.uuidString,
                            eventKind: eventKind,
                            errorCode: (error as NSError).code,
                            errorDomain: (error as NSError).domain
                        ))
                        try? repository.markCancelled(id: item.id)
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
                try? repository.markCancelled(id: item.id)
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
