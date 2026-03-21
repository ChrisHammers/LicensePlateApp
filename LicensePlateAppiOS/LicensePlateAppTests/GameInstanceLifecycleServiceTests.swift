//
//  GameInstanceLifecycleServiceTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.3 — GameInstanceLifecycleService: resetGame clears one game's events and state.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct GameInstanceLifecycleServiceTests {

    @Test func resetGameDeletesEventsAndResetsGameStateButNotSessionDates() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let gameId = UUID()
        let startedAt = Date()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: startedAt,
            endedAt: nil,
            endedBy: nil,
            participants: []
        )
        sessionRepo.seed(session)
        var game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: startedAt,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: false, configLockReason: .none)
        )
        gameRepo.seed(game)
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [TripActivityEventPayloadKey.regionId: "CA", TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]))

        let sync = MockSyncCoordinator()
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )

        try service.resetGame(sessionId: sessionId, gameInstanceId: gameId)

        let updatedSession = try sessionRepo.session(byId: sessionId)
        #expect(updatedSession?.startedAt == startedAt)
        #expect(updatedSession?.endedAt == nil)

        let regions = try eventRepo.foundRegions(sessionId: sessionId, gameInstanceId: gameId)
        #expect(regions.isEmpty)

        let updatedGame = try gameRepo.instance(byId: gameId)
        #expect(updatedGame?.commonConfig.lifecycleState == .created)
    }

    @Test func resetGameThrowsWhenTripEndedOrCancelled() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Test",
            status: .ended,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            endedAt: Date(),
            endedBy: "user1",
            participants: []
        )
        sessionRepo.seed(session)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started)
        ))

        let sync = MockSyncCoordinator()
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )

        do {
            try service.resetGame(sessionId: sessionId, gameInstanceId: gameId)
            Issue.record("Expected GameplayLifecycleRulesError.gameResetTripTerminal")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameResetTripTerminal)
        }
    }

    @Test func resetGameThrowsWhenTripCancelled() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let gameId = UUID()
        var session = TripSession(
            id: sessionId,
            name: "Test",
            status: .cancelled,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            endedAt: Date(),
            participants: []
        )
        sessionRepo.seed(session)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started)
        ))
        let sync = MockSyncCoordinator()
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )
        do {
            try service.resetGame(sessionId: sessionId, gameInstanceId: gameId)
            Issue.record("Expected gameResetTripTerminal")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameResetTripTerminal)
        }
    }

    @Test func startGameThrowsWhenTripNotStarted() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let gameId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .created,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u",
            startedAt: nil,
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: MockSyncCoordinator()
        )
        do {
            try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
            Issue.record("Expected tripNotStartedForGameStart")
        } catch let error as GameInstanceLifecycleServiceError {
            #expect(error == .tripNotStartedForGameStart)
        }
    }

    @Test func startGameSetsStartedLocksAndAppendsGameStarted() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let sessionId = UUID()
        let gameId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        let game = try gameRepo.instance(byId: gameId)
        #expect(game?.commonConfig.lifecycleState == .started)
        #expect(game?.commonConfig.configLocked == true)
        #expect(game?.commonConfig.configLockReason == .gameStarted)
        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .gameStarted && $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gameId.uuidString })
        #expect(sync.enqueueCallCount == 1)
    }

    @Test func startGameIsIdempotentWhenAlreadyStartedAndLocked() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let sessionId = UUID()
        let gameId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        #expect(eventRepo.appendedEvents().filter { $0.kind == .gameStarted }.count == 0)
        #expect(sync.enqueueCallCount == 0)
    }

    @Test func endGameSetsEndedAndAppendsGameEnded() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let sessionId = UUID()
        let gameId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )
        try service.endGame(sessionId: sessionId, gameInstanceId: gameId)
        let game = try gameRepo.instance(byId: gameId)
        #expect(game?.commonConfig.lifecycleState == .ended)
        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .gameEnded && $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gameId.uuidString })
        #expect(sync.enqueueCallCount == 1)
    }

    @Test func endGameIsIdempotentWhenAlreadyEndedOrCompleted() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sync = MockSyncCoordinator()
        let sessionId = UUID()
        let endedId = UUID()
        let completedId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: endedId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .ended, configLocked: true, configLockReason: .gameStarted)
        ))
        gameRepo.seed(GameInstance(
            id: completedId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .completed, configLocked: true, configLockReason: .gameStarted)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: sync
        )
        try service.endGame(sessionId: sessionId, gameInstanceId: endedId)
        try service.endGame(sessionId: sessionId, gameInstanceId: completedId)
        #expect(eventRepo.appendedEvents().filter { $0.kind == .gameEnded }.isEmpty)
        #expect(sync.enqueueCallCount == 0)
    }
}
