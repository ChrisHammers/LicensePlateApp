//
//  SyncCoordinator.swift
//  LicensePlateApp
//
//  Step 06.5 — Queue processing shell and user-profile sync.
//

import Foundation
import FirebaseFunctions

@MainActor
protocol SyncCoordinatorProtocol: AnyObject {
    func enqueueForSync(sessionId: UUID, eventId: String) throws
    /// Enqueues a gameplay sync item only when none exists yet for `eventId` in a non-terminal queue state.
    func ensureGameplayEventEnqueued(sessionId: UUID, eventId: String) throws
    func enqueueUserProfileSync(userId: String) throws
    func processPendingSyncItems() async
}

@MainActor
final class SyncCoordinator: SyncCoordinatorProtocol {

    static let shared = SyncCoordinator(repository: SyncQueueRepository.shared)

    private let repository: SyncQueueRepositoryProtocol
    private var userSyncExecutor: UserSyncExecutorProtocol?
    private var lastProcessPendingRunAt: Date?
    private let processPendingMinInterval: TimeInterval = 30

    init(repository: SyncQueueRepositoryProtocol, userSyncExecutor: UserSyncExecutorProtocol? = nil) {
        self.repository = repository
        self.userSyncExecutor = userSyncExecutor
    }

    func setUserSyncExecutor(_ executor: UserSyncExecutorProtocol) {
        userSyncExecutor = executor
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
        let pending = (try? repository.fetchPending(limit: 50)) ?? []
        let retryDue = (try? repository.fetchFailedRetryDue()) ?? []
        let candidates = Dictionary(uniqueKeysWithValues: (pending + retryDue).map { ($0.id, $0) }).values.sorted { $0.createdAt < $1.createdAt }

        for item in candidates where item.kind == .gameplayEvent {
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
                let outcome = try await TripCanonicalRemoteSyncService.shared.appendEventToRemote(event)
                let gameIdStr = event.payload?[TripActivityEventPayloadKey.gameInstanceId] ?? ""
                switch outcome {
                case .accepted:
                    AnalyticsService.shared.log(.gameplayEventServerAccepted(
                        tripSessionId: sessionUUID.uuidString,
                        gameInstanceId: gameIdStr,
                        eventKind: event.kind.rawValue
                    ))
                case let .superseded(localId, rejection):
                    try TripActivityEventRepository.shared.deleteEvent(id: localId)
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
                if Self.isPermanentGameplaySyncFailure(error) {
                    AnalyticsService.shared.log(.gameplayEventServerRejected(
                        tripSessionId: sessionUUID.uuidString,
                        eventKind: (try? TripActivityEventRepository.shared.event(byId: eventId))?.kind.rawValue ?? "",
                        errorCode: (error as NSError).code,
                        errorDomain: (error as NSError).domain
                    ))
                    try? repository.markCancelled(id: item.id)
                } else {
                    let attempts = max(item.attemptCount, 0) + 1
                    let delaySeconds = min(pow(2.0, Double(attempts - 1)) * 60.0, 3600.0)
                    let nextRetryAt = Date().addingTimeInterval(delaySeconds)
                    try? repository.markFailed(id: item.id, nextRetryAt: nextRetryAt)
                }
            }
        }

        guard let userSyncExecutor else { return }
        let now = Date()
        if let last = lastProcessPendingRunAt, now.timeIntervalSince(last) < processPendingMinInterval {
            return
        }
        lastProcessPendingRunAt = now

        for item in candidates where item.kind == .userProfile {
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

    private static func isPermanentGameplaySyncFailure(_ error: Error) -> Bool {
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

}
