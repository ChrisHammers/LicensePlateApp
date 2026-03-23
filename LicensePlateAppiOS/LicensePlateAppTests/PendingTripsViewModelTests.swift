//
//  PendingTripsViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 04 — PendingTripsViewModel. Step 08 — mock repository (no Firebase).
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct PendingTripsViewModelTests {

    private func auth(for userId: String) -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        auth.currentUser = testUser
        return auth
    }

    @Test func loadInvitesExposesIncomingAndOutgoing() async throws {
        let mock = MockTripInviteRepository()
        let userId = "test-user"
        let otherId = "other-user"
        let incoming = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Incoming Trip",
            fromUserId: otherId,
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(incoming)
        let outgoing = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Outgoing Trip",
            fromUserId: userId,
            toUserId: otherId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(outgoing)

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)

        #expect(viewModel.incomingInvites.count == 1)
        #expect(viewModel.incomingInvites.first?.tripName == "Incoming Trip")
        #expect(viewModel.outgoingInvites.count == 1)
        #expect(viewModel.outgoingInvites.first?.tripName == "Outgoing Trip")
    }

    @Test func acceptInviteUpdatesStatusAndRefreshesList() async throws {
        let mock = MockTripInviteRepository()
        let userId = "test-user"
        let inviteId = UUID().uuidString
        let invite = TripInvite(
            inviteId: inviteId,
            tripSessionId: UUID().uuidString,
            tripName: "Accept Test",
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(invite)

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.count == 1)

        viewModel.accept(invite: viewModel.incomingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func declineInviteUpdatesStatusAndRefreshesList() async throws {
        let mock = MockTripInviteRepository()
        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Decline Test",
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(invite)

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        viewModel.decline(invite: viewModel.incomingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
    }

    @Test func cancelInviteUpdatesOutgoing() async throws {
        let mock = MockTripInviteRepository()
        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Cancel Test",
            fromUserId: userId,
            toUserId: "other",
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(invite)

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.outgoingInvites.count == 1)
        viewModel.cancel(invite: viewModel.outgoingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.outgoingInvites.isEmpty)
    }

    @Test func displaySnapshotReflectsSeededGameCount() async throws {
        let sessionId = UUID()
        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: sessionId.uuidString,
            tripName: "Games Row Test",
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        let gameRepo = MockGameInstanceRepository()
        var g1 = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        g1.id = UUID()
        var g2 = GameInstance(
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "road_sign_bingo"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        g2.id = UUID()
        gameRepo.seed(g1)
        gameRepo.seed(g2)

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: MockTripInviteRepository(),
            authService: auth(for: userId),
            gameInstanceRepository: gameRepo
        )
        let snapshot = viewModel.displaySnapshot(for: invite)
        #expect(snapshot.gamesOnTripLine == "%d games".localized(2))
    }
}
