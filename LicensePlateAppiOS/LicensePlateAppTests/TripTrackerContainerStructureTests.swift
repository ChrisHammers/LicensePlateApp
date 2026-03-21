//
//  TripTrackerContainerStructureTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.6 Phase E — Trip container vs game surface: coordinator routes, list VM resolution,
//  and game rows scoped to GameInstance (no implicit primary-game shortcut on the active list VM).
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripTrackerContainerStructureTests {

    private func makeSession(id: UUID = UUID(), name: String = "Trip") -> TripSession {
        TripSession(
            id: id,
            name: name,
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
    }

    // MARK: - MainCoordinator / MainRoute

    @Test func openSessionAppendsSessionRouteOnly() {
        let coordinator = MainCoordinator()
        let sid = UUID()
        coordinator.openSession(sid)
        #expect(coordinator.path.count == 1)
        guard case .session(let id) = coordinator.path[0] else {
            Issue.record("Expected .session route")
            return
        }
        #expect(id == sid)
    }

    @Test func openGameAppendsGameRouteWithBothIds() {
        let coordinator = MainCoordinator()
        let sessionId = UUID()
        let gameId = UUID()
        coordinator.openGame(sessionId: sessionId, gameId: gameId)
        #expect(coordinator.path.count == 1)
        guard case .game(let sid, let gid) = coordinator.path[0] else {
            Issue.record("Expected .game route")
            return
        }
        #expect(sid == sessionId)
        #expect(gid == gameId)
    }

    @Test func sessionAndGameRoutesAreDistinctCases() {
        let s = UUID()
        let g = UUID()
        let r1 = MainCoordinator.MainRoute.session(s)
        let r2 = MainCoordinator.MainRoute.game(sessionId: s, gameId: g)
        #expect(r1 != r2)
    }

    // MARK: - ActiveTripsListViewModel: session container without primary-game helper

    @Test func sessionForResolvesWhenTripHasNoGames() async throws {
        let session = makeSession(id: UUID(), name: "Empty Games Trip")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycle = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycle
        )

        let resolved = viewModel.session(for: session.id)
        #expect(resolved != nil)
        #expect(resolved?.id == session.id)
    }

    @Test func sessionAndGameRequiresExplicitGameId() async throws {
        let session = makeSession(id: UUID(), name: "Trip With LP")
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: session.id,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let lifecycle = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycle
        )

        #expect(viewModel.sessionAndGame(sessionId: session.id, gameId: game.id) != nil)
        #expect(viewModel.sessionAndGame(sessionId: session.id, gameId: UUID()) == nil)
    }

    // MARK: - TripSessionViewModel game rows (game-scoped labels)

    @Test func gameRowItemsIncludeGameModeDisplayPerInstance() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Multi")
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(
                lifecycleState: .started,
                gameMode: .collaborative, configLocked: true,
                configLockReason: .gameStarted
            )
        )
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()

        let vm = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo
        )
        vm.load()

        #expect(vm.session != nil)
        #expect(vm.gameRowItems.count == 1)
        let row = vm.gameRowItems[0]
        #expect(row.gameModeDisplay == GameMode.collaborative.localizedDisplayName)
        #expect(row.gameId == game.id)
    }
}
