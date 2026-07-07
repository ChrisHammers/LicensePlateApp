//
//  TripSessionLifecycleService.swift
//  LicensePlateApp
//
//  Step 04 — Single orchestration path for start/end/cancel trip. Used by GameSetupViewModel and ActiveTripsListViewModel.
//  Step 6.9.3 — Per-game start/end delegated to GameInstanceLifecycleService.
//

import Foundation
import FirebaseAuth

@MainActor
protocol TripSessionLifecycleServiceProtocol: AnyObject {
    func startTrip(sessionId: UUID, actorId: String) throws
    func endTrip(sessionId: UUID, endedBy: String?) throws
    func cancelSession(sessionId: UUID, cancelledBy: String?) throws
    func applyRemoteTripEnded(sessionId: UUID, endedBy: String?, endedAt: Date?) throws -> Bool
    func reconcileRemoteTripEndedFromEventLog(userId: String?) throws -> [TripEndedRemotelyInfo]
}

@MainActor
final class TripSessionLifecycleService: TripSessionLifecycleServiceProtocol {

    static let shared = TripSessionLifecycleService(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared,
        tripActivityEventRecording: TripActivityEventRecordingService.shared,
        gameInstanceLifecycleService: GameInstanceLifecycleService.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol
    private let gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        tripActivityEventRecording: TripActivityEventRecordingProtocol,
        gameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.tripActivityEventRecording = tripActivityEventRecording
        self.gameInstanceLifecycleService = gameInstanceLifecycleService
    }

    func startTrip(sessionId: UUID, actorId: String) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.startedAt != nil {
            return
        }
        session.startedAt = Date()
        session.status = .active
        try tripSessionRepository.save(session: session)
        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        for (_, typeGames) in Dictionary(grouping: games, by: \.definitionId) {
            if typeGames.contains(where: { $0.commonConfig.lifecycleState == .started }) {
                for started in typeGames where started.commonConfig.lifecycleState == .started {
                    try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: started.id)
                }
                continue
            }
            let createdCandidates = typeGames.filter { $0.commonConfig.lifecycleState == .created }
            guard let toStart = createdCandidates.last else { continue }
            try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: toStart.id)
        }
        let tripStartedEvent = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: actorId)
        try tripActivityEventRecording.recordForSync(tripStartedEvent)
        AnalyticsService.shared.log(.tripSessionStarted(tripId: sessionId.uuidString, tripActiveGameCount: games.count))
        TripRouteTrackingService.shared.tripDidStart(sessionId: sessionId)
        Task { @MainActor in
            await ReminderNotificationService.shared.scheduleInactiveActiveTripReminder(sessionId: sessionId, tripName: session.name)
            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
        }
    }

    func endTrip(sessionId: UUID, endedBy: String?) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.status == .ended {
            return
        }
        session.endedAt = Date()
        session.endedBy = endedBy
        session.status = .ended
        try tripSessionRepository.save(session: session)
        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        for game in games {
            try gameInstanceLifecycleService.endGame(sessionId: sessionId, gameInstanceId: game.id)
        }
        let tripEndedEvent = TripActivityEvent(sessionId: sessionId, kind: .tripEnded, actorId: endedBy)
        try tripActivityEventRecording.recordForSync(tripEndedEvent)
        AnalyticsService.shared.log(.tripSessionEnded(tripId: sessionId.uuidString))
        TripRouteTrackingService.shared.tripDidEnd(sessionId: sessionId)
        ReminderNotificationService.shared.cancelReminder(sessionId: sessionId, reason: "trip_ended")
        ReviewPromptService.shared.considerPromptAfterTripCompleted(sessionId: sessionId)
        Task { @MainActor in
            let uid = endedBy ?? Auth.auth().currentUser?.uid
            if let uid {
                LifetimeStatsCoordinator.shared.onLocalTripEnded(userId: uid)
            }
            try? await TripCanonicalRemoteSyncService.shared.publishFullSession(sessionId: sessionId)
        }
    }

    @discardableResult
    func applyRemoteTripEnded(sessionId: UUID, endedBy: String?, endedAt: Date?) throws -> Bool {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        guard session.status != .ended else { return false }

        session.status = .ended
        session.endedAt = endedAt ?? Date()
        session.endedBy = endedBy
        try tripSessionRepository.save(session: session)

        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        for game in games where game.endedAt == nil {
            try gameInstanceLifecycleService.endGame(sessionId: sessionId, gameInstanceId: game.id)
        }
        TripRouteTrackingService.shared.tripDidEnd(sessionId: sessionId)
        ReminderNotificationService.shared.cancelReminder(sessionId: sessionId, reason: "trip_ended")
        return true
    }

    func reconcileRemoteTripEndedFromEventLog(userId: String?) throws -> [TripEndedRemotelyInfo] {
        guard let userId else { return [] }
        let sessions = try tripSessionRepository.loadActiveSessions(userId: userId)
        var results: [TripEndedRemotelyInfo] = []
        for session in sessions where session.status != .ended {
            let events = try tripActivityEventRepository.events(sessionId: session.id, limit: nil)
            guard let tripEnded = events.first(where: { $0.kind == .tripEnded }) else { continue }
            if try applyRemoteTripEnded(
                sessionId: session.id,
                endedBy: tripEnded.actorId,
                endedAt: tripEnded.timestamp
            ) {
                results.append(TripEndedRemotelyInfo(sessionId: session.id, endedBy: tripEnded.actorId))
            }
        }
        return results
    }

    /// Cancels the trip (soft delete UX): marks session cancelled, clears local games and all session events so scores/progress are removed.
    func cancelSession(sessionId: UUID, cancelledBy: String?) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        Task { @MainActor in
            try? await TripCanonicalRemoteSyncService.shared.markTripCancelledRemote(sessionId: sessionId)
        }
        session.status = .cancelled
        session.endedAt = Date()
        session.endedBy = cancelledBy
        try tripSessionRepository.save(session: session)
        try tripActivityEventRepository.deleteEvents(sessionId: sessionId, gameInstanceId: nil)
        try gameInstanceRepository.deleteForSession(sessionId: sessionId)
        AnalyticsService.shared.log(.tripSessionCancelled(tripId: sessionId.uuidString))
        TripRouteTrackingService.shared.tripWasCancelled(sessionId: sessionId)
        ReminderNotificationService.shared.cancelReminder(sessionId: sessionId, reason: "trip_cancelled")
    }
}

enum TripSessionLifecycleServiceError: Error, LocalizedError {
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): return "Trip session not found: \(id.uuidString)"
        }
    }
}
