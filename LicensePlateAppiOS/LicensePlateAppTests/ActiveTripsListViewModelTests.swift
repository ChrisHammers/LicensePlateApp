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
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())],
            teams: [],
            enabledCountryRawValues: ["United States"]
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
            lifecycleService: lifecycleService
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
            lifecycleService: lifecycleService
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

        let viewModel = ActiveTripsListViewModel(
            tripSessionRepository: sessionRepo,
            tripActivityEventRepository: eventRepo,
            gameInstanceRepository: gameRepo,
            lifecycleService: lifecycleService
        )
        viewModel.load(userId: "user1")
        #expect(viewModel.items.count == 1)

        viewModel.deleteSessions(at: IndexSet(integer: 0), userId: "user1")

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.pendingDeleteSessionIds.count == 1)
        #expect(viewModel.pendingDeleteSessionIds[0] == session.id)
        #expect(viewModel.pendingUserId == "user1")
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
            lifecycleService: lifecycleService
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
            lifecycleService: lifecycleService
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
            lifecycleService: lifecycleService
        )
        viewModel.load(userId: "user1")
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }
}
