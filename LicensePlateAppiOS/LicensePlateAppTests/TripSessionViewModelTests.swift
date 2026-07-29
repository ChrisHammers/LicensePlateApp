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

    // MARK: - canAddGame (button enablement only; add flow tested in GameSetupViewModelTests)

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

    @Test func canAddGame_falseWhenLiveLPExists() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Active")
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .started)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.canAddGame == false)
    }

    @Test func loadMarksStartedGameRowInProgress() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Active")
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .started)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.gameRowItems.count == 1)
        #expect(viewModel.gameRowItems[0].showsInProgressIndicator == true)
        #expect(viewModel.gameRowItems[0].gameTypeDisplay == GameType.licensePlate.displayName)
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

    // MARK: - Trip-wide plate projection (map header)

    private func licensePlateGame(
        sessionId: UUID,
        countries: [PlateRegion.Country],
        lifecycle: GameInstanceState = .started
    ) throws -> GameInstance {
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: lifecycle, gameMode: .collaborative)
        )
        game.id = UUID()
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: countries.map(\.rawValue),
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: false,
                includeCanadianTerritories: false,
                includeDC: false
            )
        )
        game.gameSpecificPayloadData = try JSONEncoder().encode(config)
        return game
    }

    private func appendFound(
        to eventRepo: MockTripActivityEventRepository,
        sessionId: UUID,
        gameId: UUID,
        regionId: String,
        participantId: String,
        at date: Date = Date()
    ) throws {
        try eventRepo.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: date,
            actorId: participantId,
            payload: [
                TripActivityEventPayloadKey.regionId: regionId,
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.participantId: participantId,
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
            ]
        ))
    }

    @Test func loadAggregatesUniqueFoundAcrossGamesAndParticipants() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Multi-game")
        let gameA = try licensePlateGame(sessionId: sessionId, countries: [.unitedStates])
        let gameB = try licensePlateGame(sessionId: sessionId, countries: [.unitedStates])
        let usGoal = LicensePlateScopeCalculator.completionGoal(for: gameA.licensePlateConfig()!)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(gameA)
        gameRepo.seed(gameB)
        let eventRepo = MockTripActivityEventRepository()
        // Same region in two games + two participants on one region → counts once
        try appendFound(to: eventRepo, sessionId: sessionId, gameId: gameA.id, regionId: "us-ca", participantId: "user1")
        try appendFound(to: eventRepo, sessionId: sessionId, gameId: gameB.id, regionId: "us-ca", participantId: "user2")
        try appendFound(to: eventRepo, sessionId: sessionId, gameId: gameA.id, regionId: "us-ny", participantId: "user2")

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.tripFoundCount == 2)
        #expect(viewModel.tripTotalCount == usGoal)
        #expect(Set(viewModel.tripFoundRegionIDs) == Set(["us-ca", "us-ny"]))
        #expect(viewModel.tripFoundRegions.count == 2)
        #expect(viewModel.tripEnabledCountries.contains(.unitedStates))
    }

    @Test func loadCountsPeerFindWithoutViewerAttribution() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Peer find",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "user1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        let game = try licensePlateGame(sessionId: sessionId, countries: [.unitedStates])

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try appendFound(to: eventRepo, sessionId: sessionId, gameId: game.id, regionId: "us-tx", participantId: "user2")

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth(userId: "user1")
        )
        viewModel.load()

        #expect(viewModel.tripFoundCount == 1)
        #expect(viewModel.tripFoundRegionIDs == ["us-tx"])
        #expect(viewModel.tripFoundRegions.first?.foundBy == "user2")
    }

    @Test func loadUnionsConfiguredScopeAcrossGames() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, name: "Scope union")
        let usGame = try licensePlateGame(sessionId: sessionId, countries: [.unitedStates])
        let caGame = try licensePlateGame(sessionId: sessionId, countries: [.canada])
        let usIds = Set(LicensePlateScopeCalculator.targetRegionIds(for: usGame.licensePlateConfig()!))
        let caIds = Set(LicensePlateScopeCalculator.targetRegionIds(for: caGame.licensePlateConfig()!))
        let expectedTotal = usIds.union(caIds).count

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(usGame)
        gameRepo.seed(caGame)
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth()
        )
        viewModel.load()

        #expect(viewModel.tripTotalCount == expectedTotal)
        #expect(viewModel.tripFoundCount == 0)
        #expect(Set(viewModel.tripEnabledCountries) == Set([.unitedStates, .canada]))
    }

    // MARK: - End trip

    @Test func canEndTripTrueForActiveDriver() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId)
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
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

        #expect(viewModel.isTripCreator == true)
        #expect(viewModel.isTripContainerActive == true)
        #expect(viewModel.canEndTrip == true)
    }

    @Test func canEndTripFalseForPassenger() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId)
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            authService: creatorAuth(userId: "passenger")
        )
        viewModel.load()

        #expect(viewModel.isTripCreator == false)
        #expect(viewModel.canEndTrip == false)
    }

    @Test func endTripDelegatesToCanonicalLifecycle() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId)
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycle = MockTripSessionLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycle,
            authService: creatorAuth()
        )
        viewModel.load()

        try viewModel.endTrip()

        #expect(lifecycle.endTripCallCount == 1)
        #expect(lifecycle.endTripSessionIds == [sessionId])
    }

    @Test func endTripThrowsForPassengerWithoutCallingLifecycle() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId)
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycle = MockTripSessionLifecycleService()

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycle,
            authService: creatorAuth(userId: "passenger")
        )
        viewModel.load()

        #expect(throws: TripSessionViewModelError.self) {
            try viewModel.endTrip()
        }
        #expect(lifecycle.endTripCallCount == 0)
    }

    @Test func endTripPropagatesLifecycleFailure() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId)
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycle = MockTripSessionLifecycleService()
        lifecycle.shouldThrow = true

        let viewModel = TripSessionViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycle,
            authService: creatorAuth()
        )
        viewModel.load()

        var didThrow = false
        do {
            try viewModel.endTrip()
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(lifecycle.endTripCallCount == 0)
    }
}
