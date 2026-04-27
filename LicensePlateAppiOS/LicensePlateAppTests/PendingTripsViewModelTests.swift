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
            gameInstanceRepository: MockGameInstanceRepository(),
            resolveInviteDisplayNames: { ids in
                Dictionary(uniqueKeysWithValues: ids.map { ($0, "dn-\($0)") })
            }
        )
        viewModel.loadInvites(userId: userId)
        try await Task.sleep(nanoseconds: 50_000_000)

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
        let entitlementService = EntitlementService(revenueCatBridge: MockRevenueCatBridge(tier: .guest))
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: MockTripSessionRepository(),
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )

        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripEntitlementGate: gate,
            resolveInviteDisplayNames: { _ in [:] }
        )
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.count == 1)

        viewModel.accept(invite: viewModel.incomingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func acceptInviteBlockedAtActiveTripLimitDoesNotAccept() async throws {
        let mock = MockTripInviteRepository()
        let sessionRepo = MockTripSessionRepository()
        let userId = "test-user"
        let inviteId = UUID().uuidString
        let invite = TripInvite(
            inviteId: inviteId,
            tripSessionId: UUID().uuidString,
            tripName: "Blocked Accept",
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(invite)
        sessionRepo.seed(TripSession(
            id: UUID(),
            name: "Existing",
            status: .created,
            createdAt: Date(),
            createdBy: userId,
            participants: [TripParticipant(userId: userId, role: .owner, joinedAt: Date())]
        ))

        let bridge = MockRevenueCatBridge(tier: .guest)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )
        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripEntitlementGate: gate,
            resolveInviteDisplayNames: { _ in [:] }
        )
        viewModel.loadInvites(userId: userId)

        viewModel.accept(invite: viewModel.incomingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(mock.acceptInviteCallCount == 0)
        #expect(viewModel.shouldPresentTripLimitPaywall)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.count == 1)
    }

    @Test func acceptInviteBelowLimitStillAccepts() async throws {
        let mock = MockTripInviteRepository()
        let sessionRepo = MockTripSessionRepository()
        let userId = "gold-user"
        let invite = TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Allowed Accept",
            fromUserId: "other",
            toUserId: userId,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
        mock.seed(invite)
        sessionRepo.seed(TripSession(id: UUID(), name: "Existing 1", status: .active, createdAt: Date(), createdBy: userId, startedAt: Date(), participants: []))
        sessionRepo.seed(TripSession(id: UUID(), name: "Existing 2", status: .created, createdAt: Date(), createdBy: userId, participants: []))

        let bridge = MockRevenueCatBridge(tier: .gold)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )
        let viewModel = PendingTripsViewModel(
            tripInviteRepository: mock,
            authService: auth(for: userId),
            gameInstanceRepository: MockGameInstanceRepository(),
            tripEntitlementGate: gate,
            resolveInviteDisplayNames: { _ in [:] }
        )
        viewModel.loadInvites(userId: userId)

        viewModel.accept(invite: viewModel.incomingInvites[0])
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(mock.acceptInviteCallCount == 1)
        #expect(viewModel.shouldPresentTripLimitPaywall == false)
        viewModel.loadInvites(userId: userId)
        #expect(viewModel.incomingInvites.isEmpty)
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
            gameInstanceRepository: MockGameInstanceRepository(),
            resolveInviteDisplayNames: { _ in [:] }
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
            gameInstanceRepository: MockGameInstanceRepository(),
            resolveInviteDisplayNames: { _ in [:] }
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
        let g1 = GameInstance(
            id: UUID(),
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        let g2 = GameInstance(
            id: UUID(),
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "road_sign_bingo"),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: true, configLockReason: .gameStarted)
        )
        gameRepo.seed(g1)
        gameRepo.seed(g2)

        let inviteRepo = MockTripInviteRepository()
        inviteRepo.seed(invite)
        let viewModel = PendingTripsViewModel(
            tripInviteRepository: inviteRepo,
            authService: auth(for: userId),
            gameInstanceRepository: gameRepo,
            resolveInviteDisplayNames: { _ in ["other": "Friend Name"] }
        )
        viewModel.loadInvites(userId: userId)
        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = viewModel.displaySnapshot(for: invite, isIncoming: true)
        #expect(snapshot.gamesOnTripLine == "%d games".localized(2))
        #expect(snapshot.counterpartyLine.contains("Friend Name"))
    }
}
