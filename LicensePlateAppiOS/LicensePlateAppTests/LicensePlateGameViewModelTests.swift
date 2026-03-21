//
//  LicensePlateGameViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 6.8 — LicensePlateGameViewModel: startTrip, submitDiscovery, removeDiscovery, persistence failures.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct LicensePlateGameViewModelTests {

    private func makeSession(id: UUID = UUID(), startedAt: Date? = nil) -> TripSession {
        TripSession(
            id: id,
            name: "Test Trip",
            status: startedAt == nil ? .created : .active,
            mode: .solo,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: startedAt,
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
    }

    private func makeGame(sessionId: UUID, lifecycleState: GameInstanceState = .created) -> GameInstance {
        var game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: lifecycleState, configLocked: false, configLockReason: .none)
        )
        game.id = UUID()
        return game
    }

    @Test func startTripCallsLifecycleAndRefreshesSession() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, startedAt: nil)
        var game = makeGame(sessionId: sessionId)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let syncCoordinator = MockSyncCoordinator()
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator
        )
        let lifecycleService = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            syncCoordinator: syncCoordinator,
            gameInstanceLifecycleService: gameLifecycle
        )
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
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
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
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

    @Test func submitDiscoveryWhenOtherParticipantAlreadyFoundSoloReturnsRejectedInvalidParticipant() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
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

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "CA", inputMethod: .list)

        guard case .rejectedInvalidParticipant = result else {
            Issue.record("Expected rejectedInvalidParticipant when other participant already found in solo, got \(result)")
            return
        }
        #expect(viewModel.rejectedInvalidParticipantMessage != nil)
        #expect(viewModel.rejectedDuplicateMessage == nil)
        #expect(eventRepo.appendedEvents().contains {
            $0.kind == .discoveryRejected
            && $0.payload?[TripActivityEventPayloadKey.regionId] == "CA"
            && $0.payload?[TripActivityEventPayloadKey.rejectionReason] == DiscoveryOutcome.rejectedInvalidParticipant.rawValue
        })
        #expect(!eventRepo.appendedEvents().contains {
            $0.kind == .regionFound
            && $0.payload?[TripActivityEventPayloadKey.regionId] == "CA"
            && $0.payload?[TripActivityEventPayloadKey.participantId] == "user1"
        })
    }

    @Test func removeDiscoveryAppendsRegionRemovedAndRefreshesFoundRegions() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
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

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        #expect(viewModel.foundRegions.contains { $0.regionID == "CA" })
        viewModel.removeDiscovery(regionID: "CA")
        #expect(!viewModel.foundRegions.contains { $0.regionID == "CA" })
        #expect(eventRepo.appendedEvents().contains { $0.kind == .regionRemoved })
    }

    @Test func updateTripNameWhenSaveThrowsSetsErrorMessageAndKeepsInMemoryName() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        sessionRepo.shouldThrow = true
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        viewModel.updateTripName("New Name")

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.currentSession.name == "New Name")
    }

    @Test func saveSessionWhenSaveThrowsSetsErrorMessage() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        sessionRepo.shouldThrow = true
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        viewModel.saveSession()

        #expect(viewModel.errorMessage != nil)
    }

    @Test func setErrorAndClearErrorUpdateErrorMessage() async throws {
        let sessionId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = UUID()

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        viewModel.setError("test error")
        #expect(viewModel.errorMessage == "test error")

        viewModel.clearError()
        #expect(viewModel.errorMessage == nil)
    }

    @Test func submitDiscoveryWhenAppendThrowsReturnsFailure() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        eventRepo.shouldThrow = true
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "CA", inputMethod: .list)

        guard case .failure(let error) = result else {
            Issue.record("Expected failure when append throws, got \(result)")
            return
        }
        #expect((error as NSError).domain == "MockTripActivityEventRepository")
    }

    @Test func commitLicensePlateScopeDraftPersistsCountriesAndTerritories() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: nil)
        var game = makeGame(sessionId: sessionId, lifecycleState: .created)
        game.id = gameId
        let initial = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: false, includeDC: true)
        )
        game.gameSpecificPayloadData = try JSONEncoder().encode(initial)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        try gameRepo.create(instance: game)
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        viewModel.beginLicensePlateScopeDraft()
        guard let draft = viewModel.licensePlateScopeDraft else {
            Issue.record("Expected license plate scope draft")
            return
        }
        draft.includeCanada = true
        draft.includeCanadianTerritories = true
        try viewModel.commitLicensePlateScopeDraft()

        #expect(viewModel.licensePlateScopeDraft == nil)
        let decoded = game.licensePlateConfig()
        #expect(decoded?.selectedCountries.contains(.unitedStates) == true)
        #expect(decoded?.selectedCountries.contains(.canada) == true)
        #expect(decoded?.territoryOptions.includeCanadianTerritories == true)
    }

    @Test func commitLicensePlateScopeDraftNormalizesTerritoriesForMexicoOnly() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: nil)
        var game = makeGame(sessionId: sessionId, lifecycleState: .created)
        game.id = gameId
        let initial = LicensePlateGameConfig(
            selectedCountriesRawValues: [
                PlateRegion.Country.unitedStates.rawValue,
                PlateRegion.Country.canada.rawValue,
                PlateRegion.Country.mexico.rawValue
            ],
            territoryOptions: LicensePlateTerritoryOptions()
        )
        game.gameSpecificPayloadData = try JSONEncoder().encode(initial)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        try gameRepo.create(instance: game)
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            syncCoordinator: MockSyncCoordinator(),
            authService: auth
        )

        viewModel.beginLicensePlateScopeDraft()
        guard let draft = viewModel.licensePlateScopeDraft else {
            Issue.record("Expected license plate scope draft")
            return
        }
        draft.includeUS = false
        draft.includeCanada = false
        draft.includeMexico = true
        draft.includeUSTerritories = true
        draft.includeDC = true
        draft.includeCanadianTerritories = true
        draft.applyParentGating()
        try viewModel.commitLicensePlateScopeDraft()

        let decoded = game.licensePlateConfig()
        #expect(decoded?.selectedCountries == [.mexico])
        #expect(decoded?.territoryOptions.includeUSTerritories == false)
        #expect(decoded?.territoryOptions.includeDC == false)
        #expect(decoded?.territoryOptions.includeCanadianTerritories == false)
    }

    @Test func gameCompletionAnalyticsGateLogsOnlyWhenCrossingGoal() {
        #expect(GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(countBefore: 0, countAfter: 1, goal: 1))
        #expect(GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(countBefore: 49, countAfter: 50, goal: 50))
        #expect(!GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(countBefore: 0, countAfter: 0, goal: 5))
        #expect(!GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(countBefore: 0, countAfter: 1, goal: 0))
        #expect(!GameCompletionAnalyticsGate.shouldLogGameInstanceCompleted(countBefore: 50, countAfter: 51, goal: 50))
    }
}
