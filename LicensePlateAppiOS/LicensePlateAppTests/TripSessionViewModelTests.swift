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

    private func makeSession(id: UUID = UUID(), name: String = "Test Trip") -> TripSession {
        TripSession(
            id: id,
            name: name,
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())],
            teams: [],
            enabledCountryRawValues: ["United States"]
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
            tripActivityEventRepository: eventRepo
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
            tripActivityEventRepository: eventRepo
        )

        viewModel.load()

        #expect(viewModel.session == nil)
        #expect(viewModel.gameRowItems.isEmpty)
    }
}
