//
//  TripVsGameActionGuardrailTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.3 — VM routes game reset to GameInstanceLifecycleService, not trip lifecycle.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripVsGameActionGuardrailTests {

    @Test func licensePlateGameViewModelResetGameUsesGameLifecycleService() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let tripLifecycle = MockTripSessionLifecycleService()
        let gameLifecycle = MockGameInstanceLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: tripLifecycle,
            gameInstanceLifecycleService: gameLifecycle,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        try viewModel.resetGame()

        #expect(gameLifecycle.resetGameCallCount == 1)
        #expect(gameLifecycle.lastResetSessionId == sessionId)
        #expect(gameLifecycle.lastResetGameInstanceId == gameId)
        #expect(tripLifecycle.startTripCallCount == 0)
        #expect(tripLifecycle.endTripCallCount == 0)
    }

    @Test func licensePlateGameViewModelDeleteTripUsesTripLifecycleCancel() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let tripLifecycle = MockTripSessionLifecycleService()
        let gameLifecycle = MockGameInstanceLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: tripLifecycle,
            gameInstanceLifecycleService: gameLifecycle,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        try viewModel.deleteTrip()

        #expect(tripLifecycle.cancelSessionCallCount == 1)
        #expect(gameLifecycle.resetGameCallCount == 0)
    }

    @Test func licensePlateGameViewModelDeleteGameInstanceUsesGameLifecycleService() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        gameRepo.seed(GameInstance(
            id: UUID(),
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.roadSignBingo.rawValue),
            commonConfig: CommonGameConfig()
        ))
        let eventRepo = MockTripActivityEventRepository()
        let tripLifecycle = MockTripSessionLifecycleService()
        let gameLifecycle = MockGameInstanceLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: tripLifecycle,
            gameInstanceLifecycleService: gameLifecycle,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        try viewModel.deleteGameInstance()

        #expect(gameLifecycle.deleteGameCallCount == 1)
        #expect(gameLifecycle.lastDeleteSessionId == sessionId)
        #expect(gameLifecycle.lastDeleteGameInstanceId == gameId)
        #expect(tripLifecycle.startTripCallCount == 0)
        #expect(tripLifecycle.cancelSessionCallCount == 0)
    }

    @Test func licensePlateGameViewModelStartGameUsesGameLifecycleService() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let tripLifecycle = MockTripSessionLifecycleService()
        let gameLifecycle = MockGameInstanceLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: tripLifecycle,
            gameInstanceLifecycleService: gameLifecycle,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        try viewModel.startGame()

        #expect(gameLifecycle.startGameCallCount == 1)
        #expect(tripLifecycle.startTripCallCount == 0)
    }

    @Test func licensePlateGameViewModelEndGameUsesGameLifecycleService() throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let tripLifecycle = MockTripSessionLifecycleService()
        let gameLifecycle = MockGameInstanceLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: tripLifecycle,
            gameInstanceLifecycleService: gameLifecycle,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        try viewModel.endGame()

        #expect(gameLifecycle.endGameCallCount == 1)
        #expect(tripLifecycle.endTripCallCount == 0)
    }
}
