//
//  TripSessionLifecycleService.swift
//  LicensePlateApp
//
//  Step 04 — Single orchestration path for start/end/reset/cancel trip. Used by CombinedTripSetupViewModel and TripTrackerViewModel.
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
        tripActivityEventRepository: TripActivityEventRepository.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
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
        try tripActivityEventRepository.append(TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: actorId))
        for game in games {
            try tripActivityEventRepository.append(TripActivityEvent(
                sessionId: sessionId,
                kind: .gameStarted,
                actorId: nil,
                payload: [TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString]
            ))
            AnalyticsService.shared.log(.gameInstanceStarted(
                gameInstanceId: game.id.uuidString,
                gameType: game.definitionId,
                gameLifecycleState: "started",
                configLockReason: ConfigLockReason.gameStarted.rawValue
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
        try tripActivityEventRepository.append(TripActivityEvent(sessionId: sessionId, kind: .tripEnded, actorId: endedBy))
        for game in games {
            try tripActivityEventRepository.append(TripActivityEvent(
                sessionId: sessionId,
                kind: .gameEnded,
                actorId: nil,
                payload: [TripActivityEventPayloadKey.gameInstanceId: game.id.uuidString]
            ))
        }
        AnalyticsService.shared.log(.tripSessionEnded(tripId: sessionId.uuidString))
    }

    func resetTrip(sessionId: UUID, gameInstanceId: UUID) throws {
        try tripActivityEventRepository.deleteEvents(sessionId: sessionId, gameInstanceId: gameInstanceId)
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        session.startedAt = nil
        session.endedAt = nil
        session.endedBy = nil
        try tripSessionRepository.save(session: session)
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

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): return "Trip session not found: \(id.uuidString)"
        }
    }
}
