//
//  TripSessionLifecycleService.swift
//  LicensePlateApp
//
//  Step 04 — Single orchestration path for start/end/cancel trip. Used by CombinedTripSetupViewModel and ActiveTripsListViewModel.
//  Step 6.9.3 — Per-game start/end delegated to GameInstanceLifecycleService.
//

import Foundation

@MainActor
protocol TripSessionLifecycleServiceProtocol: AnyObject {
    func startTrip(sessionId: UUID, actorId: String) throws
    func endTrip(sessionId: UUID, endedBy: String?) throws
    func cancelSession(sessionId: UUID, cancelledBy: String?) throws
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
        for game in games {
            try gameInstanceLifecycleService.startGame(sessionId: sessionId, gameInstanceId: game.id)
        }
        let tripStartedEvent = TripActivityEvent(sessionId: sessionId, kind: .tripStarted, actorId: actorId)
        try tripActivityEventRecording.recordForSync(tripStartedEvent)
        AnalyticsService.shared.log(.tripSessionStarted(tripId: sessionId.uuidString, tripActiveGameCount: games.count))
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
    }

    /// Cancels the trip (soft delete UX): marks session cancelled, clears local games and all session events so scores/progress are removed.
    func cancelSession(sessionId: UUID, cancelledBy: String?) throws {
        guard var session = try tripSessionRepository.session(byId: sessionId) else {
            throw TripSessionLifecycleServiceError.sessionNotFound(sessionId)
        }
        session.status = .cancelled
        session.endedAt = Date()
        session.endedBy = cancelledBy
        try tripSessionRepository.save(session: session)
        try tripActivityEventRepository.deleteEvents(sessionId: sessionId, gameInstanceId: nil)
        try gameInstanceRepository.deleteForSession(sessionId: sessionId)
        AnalyticsService.shared.log(.tripSessionCancelled(tripId: sessionId.uuidString))
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
