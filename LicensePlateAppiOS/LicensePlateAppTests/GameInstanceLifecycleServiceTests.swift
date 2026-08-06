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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        )
        do {
            try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
            Issue.record("Expected tripNotStartedForGameStart")
        } catch let error as GameInstanceLifecycleServiceError {
            #expect(error == .tripNotStartedForGameStart)
        }
    }

    @Test func startGameThrowsWhenAnotherSameTypeIsLive() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let firstId = UUID()
        let secondId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: firstId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        ))
        gameRepo.seed(GameInstance(
            id: secondId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        )
        do {
            try service.startGame(sessionId: sessionId, gameInstanceId: secondId)
            Issue.record("Expected liveGameOfTypeAlreadyExists")
        } catch let error as GameplayLifecycleRulesError {
            if case .liveGameOfTypeAlreadyExists = error {} else {
                Issue.record("Wrong error: \(error)")
            }
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
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        let assemblyStartedAt = Date().addingTimeInterval(-86_400)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: assemblyStartedAt,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        )
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        let game = try gameRepo.instance(byId: gameId)
        #expect(game?.startedAt ?? .distantPast > assemblyStartedAt)
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
            createdAt: Date(),
            createdBy: "u",
            startedAt: Date(),
            participants: []
        ))
        let priorStartedAt = Date().addingTimeInterval(-120)
        gameRepo.seed(GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: priorStartedAt,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        )
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        try service.startGame(sessionId: sessionId, gameInstanceId: gameId)
        #expect(eventRepo.appendedEvents().filter { $0.kind == .gameStarted }.count == 0)
        #expect(sync.enqueueCallCount == 0)
        #expect(try gameRepo.instance(byId: gameId)?.startedAt == priorStartedAt)
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        )
        try service.endGame(sessionId: sessionId, gameInstanceId: gameId)
        let game = try gameRepo.instance(byId: gameId)
        #expect(game?.commonConfig.lifecycleState == .ended)
        #expect(game?.endedAt != nil)
        let appended = eventRepo.appendedEvents()
        #expect(appended.contains { $0.kind == .gameEnded && $0.payload?[TripActivityEventPayloadKey.gameInstanceId] == gameId.uuidString })
        #expect(sync.enqueueCallCount == 1)
    }

    @Test func applyRemoteGameLifecycleEventGameEndedUpdatesLocalInstance() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let gameId = UUID()
        let endedAt = Date()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
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
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: eventRepo,
                syncCoordinator: MockSyncCoordinator()
            )
        )
        let event = TripActivityEvent(
            sessionId: sessionId,
            kind: .gameEnded,
            timestamp: endedAt,
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]
        )
        let applied = try service.applyRemoteGameLifecycleEvent(event)
        #expect(applied == true)
        let game = try gameRepo.instance(byId: gameId)
        #expect(game?.commonConfig.lifecycleState == .ended)
        #expect(game?.endedAt == endedAt)
    }

    @Test func endGameIsIdempotentWhenAlreadyEndedButAllowsCompletedToEnded() async throws {
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        )
        try service.endGame(sessionId: sessionId, gameInstanceId: endedId)
        try service.endGame(sessionId: sessionId, gameInstanceId: completedId)
        #expect(eventRepo.appendedEvents().filter { $0.kind == .gameEnded }.count == 1)
        #expect(sync.enqueueCallCount == 1)
        let completed = try gameRepo.instance(byId: completedId)
        #expect(completed?.commonConfig.lifecycleState == .ended)
    }

    @Test func markGameFullClearSetsCompletedThenAutoEnds() async throws {
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: sync)
        )
        try service.markGameFullClear(sessionId: sessionId, gameInstanceId: gameId)
        try service.markGameFullClear(sessionId: sessionId, gameInstanceId: gameId)
        let appended = eventRepo.appendedEvents()
        #expect(appended.filter { $0.kind == .gameCompleted }.count == 1)
        #expect(appended.filter { $0.kind == .gameEnded }.count == 1)
        let updated = try gameRepo.instance(byId: gameId)
        #expect(updated?.commonConfig.lifecycleState == .ended)
        #expect(updated?.endedAt != nil)
    }

    @Test func deleteGameRemovesInstanceAndEventsWhenMultipleGames() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let keepId = UUID()
        let removeId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .created,
            createdAt: Date(),
            createdBy: "u",
            startedAt: nil,
            participants: []
        ))
        gameRepo.seed(GameInstance(
            id: keepId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig()
        ))
        gameRepo.seed(GameInstance(
            id: removeId,
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.roadSignBingo.rawValue),
            commonConfig: CommonGameConfig()
        ))
        try eventRepo.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .gameStarted,
            payload: [TripActivityEventPayloadKey.gameInstanceId: removeId.uuidString]
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        )
        try service.deleteGame(sessionId: sessionId, gameInstanceId: removeId)
        #expect(try gameRepo.instance(byId: removeId) == nil)
        #expect(try gameRepo.instance(byId: keepId) != nil)
        #expect(try gameRepo.gameCount(sessionId: sessionId) == 1)
        #expect(eventRepo.appendedEvents().filter { $0.kind == .gameStarted }.isEmpty)
    }

    @Test func deleteGameThrowsWhenOnlyOneGameInSession() async throws {
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let sessionId = UUID()
        let gameId = UUID()
        sessionRepo.seed(TripSession(
            id: sessionId,
            name: "T",
            status: .active,
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
            commonConfig: CommonGameConfig()
        ))
        let service = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        )
        do {
            try service.deleteGame(sessionId: sessionId, gameInstanceId: gameId)
            Issue.record("Expected gameDeleteLastGameNotAllowed")
        } catch let error as GameplayLifecycleRulesError {
            #expect(error == .gameDeleteLastGameNotAllowed)
        }
    }
}
