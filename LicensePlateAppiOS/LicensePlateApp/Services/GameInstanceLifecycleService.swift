//
//  GameInstanceLifecycleService.swift
//  LicensePlateApp
//
//  Step 6.9.3 — Game-level lifecycle: start, end, reset, delete instance. Trip container orchestration stays in TripSessionLifecycleService.
//

import Foundation

enum GameInstanceLifecycleServiceError: Error, Equatable, LocalizedError {
    case sessionNotFound(UUID)
    case gameNotFound(UUID)
    case gameNotInSession(gameInstanceId: UUID, sessionId: UUID)
    case tripNotStartedForGameStart
    case sessionCancelled

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Trip session not found: \(id.uuidString)"
        case .gameNotFound(let id):
            return "Game instance not found: \(id.uuidString)"
        case .gameNotInSession(let gameId, let sessionId):
            return "Game \(gameId.uuidString) does not belong to session \(sessionId.uuidString)"
        case .tripNotStartedForGameStart:
            return "Start the trip before starting games.".localized
        case .sessionCancelled:
            return "This trip was cancelled.".localized
        }
    }
}

@MainActor
protocol GameInstanceLifecycleServiceProtocol: AnyObject {
    func startGame(sessionId: UUID, gameInstanceId: UUID) throws
    func endGame(sessionId: UUID, gameInstanceId: UUID) throws
    func resetGame(sessionId: UUID, gameInstanceId: UUID) throws
    /// Removes this game from the trip (events + SwiftData row). Requires at least one other game on the session.
    func deleteGame(sessionId: UUID, gameInstanceId: UUID) throws
}

@MainActor
final class GameInstanceLifecycleService: GameInstanceLifecycleServiceProtocol {

    static let shared = GameInstanceLifecycleService(
        tripSessionRepository: TripSessionRepository.shared,
        gameInstanceRepository: GameInstanceRepository.shared,
        tripActivityEventRepository: TripActivityEventRepository.shared,
        tripActivityEventRecording: TripActivityEventRecordingService.shared
    )

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let gameInstanceRepository: GameInstanceRepositoryProtocol
    private let tripActivityEventRepository: TripActivityEventRepositoryProtocol
    private let tripActivityEventRecording: TripActivityEventRecordingProtocol

    init(
        tripSessionRepository: TripSessionRepositoryProtocol,
        gameInstanceRepository: GameInstanceRepositoryProtocol,
        tripActivityEventRepository: TripActivityEventRepositoryProtocol,
        tripActivityEventRecording: TripActivityEventRecordingProtocol
    ) {
        self.tripSessionRepository = tripSessionRepository
        self.gameInstanceRepository = gameInstanceRepository
        self.tripActivityEventRepository = tripActivityEventRepository
        self.tripActivityEventRecording = tripActivityEventRecording
    }

    /// Transitions one game to started, locks config, appends `gameStarted`, sync enqueue, analytics. Idempotent if already started+locked.
    func startGame(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw GameInstanceLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.status == .cancelled {
            throw GameInstanceLifecycleServiceError.sessionCancelled
        }
        guard session.startedAt != nil, session.status == .active else {
            throw GameInstanceLifecycleServiceError.tripNotStartedForGameStart
        }
        guard var game = try gameInstanceRepository.instance(byId: gameInstanceId) else {
            throw GameInstanceLifecycleServiceError.gameNotFound(gameInstanceId)
        }
        guard game.sessionId == sessionId else {
            throw GameInstanceLifecycleServiceError.gameNotInSession(gameInstanceId: gameInstanceId, sessionId: sessionId)
        }
        if game.commonConfig.lifecycleState == .started && game.commonConfig.configLocked {
            return
        }
        game.commonConfig.lifecycleState = .started
        game.commonConfig.configLocked = true
        game.commonConfig.configLockReason = .gameStarted
        try gameInstanceRepository.update(instance: game)

        let gameStartedEvent = TripActivityEvent(
            sessionId: sessionId,
            kind: .gameStarted,
            actorId: nil,
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameInstanceId.uuidString]
        )
        try tripActivityEventRecording.recordForSync(gameStartedEvent)
        AnalyticsService.shared.log(.gameInstanceStarted(
            gameInstanceId: gameInstanceId.uuidString,
            gameType: game.definitionId,
            gameLifecycleState: GameInstanceState.started.rawValue,
            configLockReason: ConfigLockReason.gameStarted.rawValue,
            tripSessionId: sessionId.uuidString
        ))
    }

    /// Marks game ended, appends `gameEnded`, sync enqueue, analytics. Idempotent if already ended or completed.
    func endGame(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw GameInstanceLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.status == .cancelled {
            throw GameInstanceLifecycleServiceError.sessionCancelled
        }
        guard var game = try gameInstanceRepository.instance(byId: gameInstanceId) else {
            throw GameInstanceLifecycleServiceError.gameNotFound(gameInstanceId)
        }
        guard game.sessionId == sessionId else {
            throw GameInstanceLifecycleServiceError.gameNotInSession(gameInstanceId: gameInstanceId, sessionId: sessionId)
        }
        if game.commonConfig.lifecycleState == .ended || game.commonConfig.lifecycleState == .completed {
            return
        }
        game.commonConfig.lifecycleState = .ended
        try gameInstanceRepository.update(instance: game)

        let gameEndedEvent = TripActivityEvent(
            sessionId: sessionId,
            kind: .gameEnded,
            actorId: nil,
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameInstanceId.uuidString]
        )
        try tripActivityEventRecording.recordForSync(gameEndedEvent)
        AnalyticsService.shared.log(.gameInstanceEnded(
            gameInstanceId: gameInstanceId.uuidString,
            gameType: game.definitionId,
            tripSessionId: sessionId.uuidString
        ))
    }

    /// Clears discovery-related events for this game and sets lifecycle to `created`. Trip dates and status unchanged.
    func resetGame(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw GameInstanceLifecycleServiceError.sessionNotFound(sessionId)
        }
        try GameplayLifecycleRules.validateGameResetAllowed(tripSessionState: session.status)
        try tripActivityEventRepository.deleteEvents(sessionId: sessionId, gameInstanceId: gameInstanceId)
        if var game = try gameInstanceRepository.instance(byId: gameInstanceId) {
            game.commonConfig.lifecycleState = .created
            try gameInstanceRepository.update(instance: game)
        }
        AnalyticsService.shared.log(.gameInstanceReset(tripSessionId: sessionId.uuidString, gameInstanceId: gameInstanceId.uuidString))
    }

    /// Deletes persisted events tagged with this game, then removes the `GameInstance`. Does not end the trip.
    func deleteGame(sessionId: UUID, gameInstanceId: UUID) throws {
        guard let session = try tripSessionRepository.session(byId: sessionId) else {
            throw GameInstanceLifecycleServiceError.sessionNotFound(sessionId)
        }
        if session.status == .cancelled {
            throw GameInstanceLifecycleServiceError.sessionCancelled
        }
        let gameCount = try gameInstanceRepository.gameCount(sessionId: sessionId)
        try GameplayLifecycleRules.validateGameDeleteAllowed(tripSessionState: session.status, gameCountInSession: gameCount)
        guard let game = try gameInstanceRepository.instance(byId: gameInstanceId) else {
            throw GameInstanceLifecycleServiceError.gameNotFound(gameInstanceId)
        }
        guard game.sessionId == sessionId else {
            throw GameInstanceLifecycleServiceError.gameNotInSession(gameInstanceId: gameInstanceId, sessionId: sessionId)
        }
        try tripActivityEventRepository.deleteAllEventsForGame(sessionId: sessionId, gameInstanceId: gameInstanceId)
        try gameInstanceRepository.delete(instanceId: gameInstanceId)
        let remaining = gameCount - 1
        AnalyticsService.shared.log(.gameInstanceDeleted(
            tripSessionId: sessionId.uuidString,
            gameInstanceId: gameInstanceId.uuidString,
            gameType: game.definitionId,
            remainingGameCount: remaining
        ))
    }
}
