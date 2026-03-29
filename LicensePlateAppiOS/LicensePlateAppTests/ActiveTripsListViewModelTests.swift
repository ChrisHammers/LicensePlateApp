//
//  ActiveTripsListViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 05 — ActiveTripsListViewModel: load/delete failure cases, clearError, retryLastDelete.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct ActiveTripsListViewModelTests {

    private func makeSession(id: UUID = UUID(), name: String = "Trip") -> TripSession {
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

    @Test func loadWhenSessionRepoThrowsSetsErrorMessageAndEmptyItems() async throws {
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.shouldThrow = true
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        viewModel.load(userId: "user1")

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.errorMessage?.isEmpty == false)
    }

    @Test func loadWhenSessionRepoSucceedsClearsErrorAndPopulatesItems() async throws {
        let session = makeSession(name: "Active One")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        viewModel.load(userId: "user1")

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.items.count == 1)
        #expect(viewModel.items[0].session.name == "Active One")
    }

    @Test func deleteSessionsWhenLifecycleThrowsSetsErrorMessageAndPendingState() async throws {
        let session = makeSession(name: "To Delete")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        lifecycleService.shouldThrow = true
        let participation = MockTripParticipationService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: participation
        )
        viewModel.load(userId: "user1")
        #expect(viewModel.items.count == 1)

        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "user1")

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.pendingDeleteSessionIds.count == 1)
        #expect(viewModel.pendingDeleteSessionIds[0] == session.id)
        #expect(viewModel.pendingUserId == "user1")
        #expect(participation.initiateLeaveTripCallCount == 0)
    }

    @Test func retryLastDeleteWhenStillFailingKeepsErrorMessage() async throws {
        let session = makeSession(name: "To Delete")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        lifecycleService.shouldThrow = true

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )
        viewModel.load(userId: "user1")
        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "user1")
        #expect(viewModel.errorMessage != nil)

        viewModel.retryLastDelete()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.pendingDeleteSessionIds.count == 1)
    }

    @Test func retryLastDeleteWhenSucceedsClearsErrorAndPending() async throws {
        let session = makeSession(name: "To Delete")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        lifecycleService.shouldThrow = true

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )
        viewModel.load(userId: "user1")
        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "user1")
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.pendingDeleteSessionIds.isEmpty)

        lifecycleService.shouldThrow = false
        viewModel.retryLastDelete()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.pendingDeleteSessionIds.isEmpty)
        #expect(viewModel.pendingUserId == nil)
    }

    @Test func clearErrorSetsErrorMessageToNil() async throws {
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.shouldThrow = true
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )
        viewModel.load(userId: "user1")
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - Step 6.8 — session(for:) and sessionAndGame(sessionId:gameId:)

    @Test func sessionForWhenSessionExistsReturnsSession() async throws {
        let session = makeSession(id: UUID(), name: "Seeded Trip")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        let result = viewModel.session(for: session.id)

        #expect(result != nil)
        #expect(result?.id == session.id)
        #expect(result?.name == "Seeded Trip")
    }

    @Test func sessionForWhenSessionMissingReturnsNil() async throws {
        let sessionRepo = MockTripSessionRepository()
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        let result = viewModel.session(for: UUID())

        #expect(result == nil)
    }

    @Test func sessionAndGameWhenBothExistReturnsTuple() async throws {
        let session = makeSession(id: UUID(), name: "Trip With Game")
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
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        let result = viewModel.sessionAndGame(sessionId: session.id, gameId: game.id)

        #expect(result != nil)
        #expect(result!.0.id == session.id)
        #expect(result!.1.id == game.id)
    }

    @Test func sessionAndGameWhenSessionMissingReturnsNil() async throws {
        let sessionRepo = MockTripSessionRepository()
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        let result = viewModel.sessionAndGame(sessionId: UUID(), gameId: UUID())

        #expect(result == nil)
    }

    @Test func sessionAndGameWhenGameMissingReturnsNil() async throws {
        let session = makeSession(id: UUID(), name: "Trip No Game")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: MockTripParticipationService()
        )

        let result = viewModel.sessionAndGame(sessionId: session.id, gameId: UUID())

        #expect(result == nil)
    }

    @Test func deleteSessionsWhenUserIsNotCreatorCallsLeaveNotCancel() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Shared",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "joiner1", role: .member, joinedAt: Date())
            ]
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let participation = MockTripParticipationService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: participation
        )
        viewModel.load(userId: "joiner1")
        #expect(viewModel.items.count == 1)

        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "joiner1")

        #expect(viewModel.errorMessage == nil)
        #expect(lifecycleService.cancelSessionCallCount == 0)
        #expect(participation.initiateLeaveTripCallCount == 1)
        #expect(participation.lastLeaveSessionId == sessionId)
        #expect(participation.lastLeaveUserId == "joiner1")
        // Mock leave does not mutate MockTripSessionRepository; list may still show the trip until a real leave runs.
    }

    @Test func deleteSessionsWhenUserIsCreatorCallsCancelNotLeave() async throws {
        let session = makeSession(name: "Mine")
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let eventRepo = MockTripActivityEventRepository()
        let gameRepo = MockGameInstanceRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let participation = MockTripParticipationService()

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService,
            participationService: participation
        )
        viewModel.load(userId: "user1")
        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "user1")

        #expect(lifecycleService.cancelSessionCallCount == 1)
        #expect(participation.initiateLeaveTripCallCount == 0)
    }
}
