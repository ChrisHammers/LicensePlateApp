//
//  PendingTripsViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 04 — PendingTripsViewModel: load invites from repository, accept/decline/cancel.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct PendingTripsViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    @Test func loadInvitesExposesIncomingAndOutgoing() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = TripInviteRepository.shared
        repo.setModelContext(ctx)

        let userId = "test-user"
        let otherId = "other-user"
        let incoming = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Incoming Trip",
            tripMode: TripMode.solo.rawValue,
            fromUserId: otherId,
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(incoming)
        let outgoing = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Outgoing Trip",
            tripMode: TripMode.multiplayer.rawValue,
            fromUserId: userId,
            toUserId: otherId,
            status: .sent,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(outgoing)
        try ctx.save()

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: repo,
            authService: auth,
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)

        #expect(viewModel.incomingInvites.count == 1)
        #expect(viewModel.incomingInvites.first?.tripName == "Incoming Trip")
        #expect(viewModel.outgoingInvites.count == 1)
        #expect(viewModel.outgoingInvites.first?.tripName == "Outgoing Trip")
    }

    @Test func acceptInviteUpdatesStatusAndRefreshesList() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = TripInviteRepository.shared
        repo.setModelContext(ctx)

        let userId = "test-user"
        let inviteId = UUID().uuidString
        let invite = TripInvite(
            inviteId: inviteId,
            tripSessionId: UUID().uuidString,
            tripName: "Accept Test",
            tripMode: TripMode.solo.rawValue,
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(invite)
        try ctx.save()

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: repo,
            authService: auth,
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.count == 1)

        viewModel.accept(invite: viewModel.incomingInvites[0])
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func declineInviteUpdatesStatusAndRefreshesList() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = TripInviteRepository.shared
        repo.setModelContext(ctx)

        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Decline Test",
            tripMode: TripMode.solo.rawValue,
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(invite)
        try ctx.save()

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: repo,
            authService: auth,
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        viewModel.decline(invite: viewModel.incomingInvites[0])
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
    }

    @Test func cancelInviteUpdatesOutgoing() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = TripInviteRepository.shared
        repo.setModelContext(ctx)

        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Cancel Test",
            tripMode: TripMode.solo.rawValue,
            fromUserId: userId,
            toUserId: "other",
            status: .sent,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(invite)
        try ctx.save()

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: repo,
            authService: auth,
            gameInstanceRepository: MockGameInstanceRepository()
        )
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.outgoingInvites.count == 1)
        viewModel.cancel(invite: viewModel.outgoingInvites[0])
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.outgoingInvites.isEmpty)
    }

    @Test func displaySnapshotReflectsSeededGameCount() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let inviteRepo = TripInviteRepository.shared
        inviteRepo.setModelContext(ctx)

        let sessionId = UUID()
        let userId = "test-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: sessionId.uuidString,
            tripName: "Games Row Test",
            tripMode: TripMode.multiplayer.rawValue,
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        ctx.insert(invite)
        try ctx.save()

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

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: inviteRepo,
            authService: auth,
            gameInstanceRepository: gameRepo
        )
        let snapshot = viewModel.displaySnapshot(for: invite)
        #expect(snapshot.gamesOnTripLine == "%d games".localized(2))
    }
}
