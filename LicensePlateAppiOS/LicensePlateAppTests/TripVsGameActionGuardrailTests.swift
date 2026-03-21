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
}
