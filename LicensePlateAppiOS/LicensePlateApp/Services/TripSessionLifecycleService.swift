//
//  TripSessionLifecycleService.swift
//  LicensePlateApp
//
//  Step 04 — Single orchestration path for start/end/reset/cancel trip. Used by CombinedTripSetupViewModel and LicensePlateGameViewModel.
//  Step 6.9.1 — resetTrip resets the specified game only (events + game state). Fails if trip is ended. Does not alter trip-level lifecycle.
//

import Foundation

@MainActor
protocol TripSessionLifecycleServiceProtocol: AnyObject {
    func startTrip(sessionId: UUID, actorId: String) throws
    func endTrip(sessionId: UUID, endedBy: String?) throws
    func resetTrip(sessionId: UUID, gameInstanceId: UUID) throws
    func cancelSession(sessionId: UUID, cancelledBy: String?) throws
}

@MainActor
final class TripSessionLifecycleService: TripSessionLifecycleServiceProtocol {

    static let shared = TripSessionLifecycleService(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared,
        syncCoordinator: SyncCoordinator.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let syncCoordinator: SyncCoordinatorProtocol

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        syncCoordinator: SyncCoordinatorProtocol
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.syncCoordinator = syncCoordinator
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
        try gameInstanceRepository.transitionGamesToStarted(sessionId: sessionId)
        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        let tripStartedEvent = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: actorId)
        try tripActivityEventRepository.append(tripStartedEvent)
        try syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: tripStartedEvent.id)
        for game in games {
            let gameStartedEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .gameStarted,
                actorId: nil,
                payload: [TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString]
            )
            try tripActivityEventRepository.append(gameStartedEvent)
            try syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: gameStartedEvent.id)
            AnalyticsService.shared.log(.gameInstanceStarted(
                gameInstanceId: game.id.uuidString,
                gameType: game.definitionId,
                gameLifecycleState: "started",
                configLockReason: ConfigLockReason.gameStarted.rawValue,
                tripSessionId: sessionId.uuidString
            ))
        }
        AnalyticsService.shared.log(.tripSessionStarted(tripId: sessionId.uuidString, tripActiveGameCount: games.count))
    }

    func endTrip(sessionId: UUID, endedBy: String?) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        session.endedAt = Date()
        session.endedBy = endedBy
        session.status = .ended
        try tripSessionRepository.save(session: session)
        let games = try gameInstanceRepository.fetchByTripSession(sessionId: sessionId)
        let tripEndedEvent = TripActivityEvent(sessionId: sessionId, kind: .tripEnded, actorId: endedBy)
        try tripActivityEventRepository.append(tripEndedEvent)
        try syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: tripEndedEvent.id)
        for game in games {
            let gameEndedEvent = TripActivityEvent(
                sessionId: sessionId,
                kind: .gameEnded,
                actorId: nil,
                payload: [TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString]
            )
            try tripActivityEventRepository.append(gameEndedEvent)
            try syncCoordinator.enqueueForSync(sessionId: sessionId, eventId: gameEndedEvent.id)
            AnalyticsService.shared.log(.gameInstanceEnded(gameInstanceId: game.id.uuidString, gameType: game.definitionId, tripSessionId: sessionId.uuidString))
        }
        AnalyticsService.shared.log(.tripSessionEnded(tripId: sessionId.uuidString))
        AnalyticsService.shared.log(.tripSessionCompleted(tripId: sessionId.uuidString))
    }

    /// Resets the specified game only (events + game state). Fails if trip is ended. Does not alter trip-level lifecycle (startedAt, endedAt, endedBy).
    func resetTrip(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.status == .ended {
            throw TripSessionLifecycleServiceError.tripAlreadyEnded
        }
        try tripActivityEventRepository.deleteEvents(sessionId: sessionId, gameInstanceId: gameInstanceId)
        if var game = try gameInstanceRepository.instance(byId: gameInstanceId) {
            game.commonConfig.lifecycleState = .created
            try gameInstanceRepository.update(instance: game)
        }
        AnalyticsService.shared.log(.tripSessionReset(tripId: sessionId.uuidString, gameInstanceId: gameInstanceId.uuidString))
    }

    func cancelSession(sessionId: UUID, cancelledBy: String?) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        session.status = .cancelled
        session.endedAt = Date()
        try tripSessionRepository.save(session: session)
        AnalyticsService.shared.log(.tripSessionDeleted(tripId: sessionId.uuidString))
    }
}

enum TripSessionLifecycleServiceError: Error, LocalizedError {
    case sessionNotFound(UUID)
    case tripAlreadyEnded

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): return "Trip session not found: \(id.uuidString)"
        case .tripAlreadyEnded: return "Trip already ended".localized
        }
    }
}
