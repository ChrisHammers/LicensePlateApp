//
//  TripTrackerViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 04 — TripTrackerViewModel: startTrip, submitDiscovery, removeDiscovery.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripTrackerViewModelTests {

    private func makeSession(id: UUID = UUID(), startedAt: Date? = nil) -> TripSession {
        TripSession(
            id: id,
            name: "Test Trip",
            status: .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: startedAt,
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())],
            teams: [],
            enabledCountryRawValues: ["United States"]
        )
    }

    private func makePrimaryGame(sessionId: UUID, lifecycleState: GameLifecycleState = .created) -> GameInstance {
        GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            commonConfig: CommonGameConfig(lifecycleState: lifecycleState, configLocked: false, configLockReason: .none),
            ruleSet: GameRuleSet()
        )
    }

    @Test func startTripCallsLifecycleAndRefreshesSession() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, startedAt: nil)
        var game = makePrimaryGame(sessionId: sessionId)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)

        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)

        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo
        )
        let auth = FirebaseAuthService()
        let user = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        auth.currentUser = user

        let viewModel = TripTrackerViewModel(
            session: session,
            primaryGame: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            authService: auth
        )

        try viewModel.startTrip()

        #expect(viewModel.currentSession.startedAt != nil)
        #expect(eventRepo.appendedEvents().contains { $0.kind == .tripStarted })
    }

    @Test func submitDiscoveryWithNoExistingReturnsSuccessAndAppendsEvent() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makePrimaryGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = TripTrackerViewModel(
            session: session,
            primaryGame: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "CA", inputMethod: .list)

        guard case .success = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(viewModel.foundRegions.contains { $0.regionID == "CA" })
        #expect(eventRepo.appendedEvents().contains { $0.kind == .regionFound && $0.payload?[TripActivityEventPayloadKey.regionId] == "CA" })
    }

    @Test func submitDiscoveryWhenOtherParticipantAlreadyFoundSoloReturnsRejectedDuplicate() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makePrimaryGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, actorId: "otherUser", payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "otherUser",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = TripTrackerViewModel(
            session: session,
            primaryGame: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "CA", inputMethod: .list)

        guard case .rejectedDuplicate = result else {
            Issue.record("Expected rejectedDuplicate when other participant already found in solo, got \(result)")
            return
        }
        #expect(viewModel.rejectedDuplicateMessage != nil)
    }

    @Test func removeDiscoveryAppendsRegionRemovedAndRefreshesFoundRegions() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makePrimaryGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(sessionId: sessionId, kind: .regionFound, payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString
        ]))
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()

        let viewModel = TripTrackerViewModel(
            session: session,
            primaryGame: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            authService: auth
        )

        #expect(viewModel.foundRegions.contains { $0.regionID == "CA" })
        viewModel.removeDiscovery(regionID: "CA")
        #expect(!viewModel.foundRegions.contains { $0.regionID == "CA" })
        #expect(eventRepo.appendedEvents().contains { $0.kind == .regionRemoved })
    }
}
