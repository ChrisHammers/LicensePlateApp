//
//  TripSessionViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 6.8 — TripSessionViewModel: load() populates session and gameRowItems; session not found yields nil/empty.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSessionViewModelTests {

    private func creatorAuth(userId: String = "user1") -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: userId, userName: "U", firebaseUID: userId)
        return auth
    }

    private func makeSession(id: UUID = UUID(), name: String = "Test Trip") -> TripSession {
        TripSession(
            id: id,
            name: name,
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
    }

    private func makeGame(sessionId: UUID) -> GameInstance {
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        game.id = UUID()
        return game
    }

    @Test func loadWhenSessionExistsPopulatesSessionAndGameRowItems() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "My Trip")
        var game = makeGame(sessionId: sessionId)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )

        viewModel.load()

        #expect(viewModel.session != nil)
        #expect(viewModel.session?.id == sessionId)
        #expect(viewModel.session?.name == "My Trip")
        #expect(viewModel.gameRowItems.count == 1)
        let row = viewModel.gameRowItems[0]
        #expect(row.gameId == game.id)
        #expect(row.definitionId == GameType.licensePlate.rawValue)
        #expect(row.isEnterable == true)
    }

    @Test func loadWhenSessionMissingSetsNilAndEmpty() async throws {
        let sessionId = UUID()
        let sessionRepo = MockTripSessionRepository()
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )

        viewModel.load()

        #expect(viewModel.session == nil)
        #expect(viewModel.gameRowItems.isEmpty)
    }

    // MARK: - addGame (second license plate)

    private func makeCreatedSession(id: UUID) -> TripSession {
        TripSession(
            id: id,
            name: "Created Trip",
            status: .created,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: nil,
            endedAt: nil,
            endedBy: nil,
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
    }

    private func licensePlateInstance(sessionId: UUID, lifecycle: GameInstanceState) -> GameInstance {
        var g = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: lifecycle, gameMode: .collaborative)
        )
        g.id = UUID()
        return g
    }

    @Test func addGame_whenCreatedTripAndOneLP_addsSecondLPWithoutStarting() async throws {
        let sessionId = UUID()
        let session = makeCreatedSession(id: sessionId)
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .created)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth()
        )

        viewModel.addGame()

        let games = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(games.count == 2)
        #expect(games.allSatisfy { $0.definitionId == GameType.licensePlate.rawValue })
        #expect(gameLifecycle.startGameCallCount == 0)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func addGame_whenActiveTripAndOneLP_addsSecondLPAndCallsStartGame() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Active")
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .started)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth()
        )

        viewModel.addGame()

        let games = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(games.count == 2)
        #expect(games.allSatisfy { $0.definitionId == GameType.licensePlate.rawValue })
        #expect(gameLifecycle.startGameCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func addGame_whenPassenger_setsErrorAndDoesNotCreate() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Multi Trip",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .started)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth(userId: "user2")
        )

        viewModel.addGame()

        #expect(try gameRepo.fetchByTripSession(sessionId: sessionId).count == 1)
        #expect(viewModel.errorMessage != nil)
        #expect(gameLifecycle.startGameCallCount == 0)
    }

    @Test func addGame_whenTripEnded_setsErrorAndDoesNotCreate() async throws {
        let sessionId = UUID()
        var session = makeSession(id: sessionId, name: "Over")
        session.status = .ended
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .ended)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth()
        )

        viewModel.addGame()

        #expect(try gameRepo.fetchByTripSession(sessionId: sessionId).count == 1)
        #expect(viewModel.errorMessage != nil)
        #expect(gameLifecycle.startGameCallCount == 0)
    }

    @Test func addGame_whenTripCancelled_setsErrorAndDoesNotCreate() async throws {
        let sessionId = UUID()
        var session = makeSession(id: sessionId, name: "Cancelled")
        session.status = .cancelled
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .created)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth()
        )

        viewModel.addGame()

        #expect(try gameRepo.fetchByTripSession(sessionId: sessionId).count == 1)
        #expect(viewModel.errorMessage != nil)
        #expect(gameLifecycle.startGameCallCount == 0)
    }

    // MARK: - Step 12 Trip dashboard competitive leaderboard

    @Test func loadPopulatesTripLeaderboardWhenMultiplayerAndCompetitiveGame() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Competitive Trip",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "user1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig(lifecycleState: .started, gameMode: .competitive)
        )
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "us-ca",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, actorId: "user2", payload: [
            TripActivityEventPayloadKey.regionId: "us-ny",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user2",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.showsTripCompetitiveLeaderboard == true)
        #expect(viewModel.tripLeaderboardRows.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: viewModel.tripLeaderboardRows.map { ($0.contribution.participantId, $0) })
        #expect(byId["user1"]?.contribution.weightedScore == 1.0)
        #expect(byId["user2"]?.contribution.weightedScore == 1.0)
        #expect(byId["user1"]?.rank == 1)
        #expect(byId["user2"]?.rank == 1)
        #expect(byId["user1"]?.isTiedOnScore == true)
        #expect(byId["user2"]?.isTiedOnScore == true)
    }

    @Test func loadHidesTripLeaderboardWhenOnlyCollaborativeGames() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Collab")
        var game = makeGame(sessionId: sessionId)
        game.commonConfig.gameMode = .collaborative

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.showsTripCompetitiveLeaderboard == false)
        #expect(viewModel.tripLeaderboardRows.isEmpty)
    }
}
