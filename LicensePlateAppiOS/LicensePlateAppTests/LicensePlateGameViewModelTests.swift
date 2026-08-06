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
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: syncCoordinator)
        let gameLifecycle = GameInstanceLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: recording
        )
        let lifecycleService = TripSessionLifecycleService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            tripActivityEventRecording: recording,
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
            tripActivityEventRecording: recording,
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "CA", inputMethod: .list)

        guard case .success = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(viewModel.foundRegions.contains { $0.regionID == "CA" })
        let regionFound = eventRepo.appendedEvents().last { $0.kind == .regionFound && $0.payload?[TripActivityEventPayloadKey.regionId] == "CA" }
        #expect(regionFound != nil)
        #expect(regionFound?.payload?[TripActivityEventPayloadKey.discoveryEventId] == regionFound?.id)
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            && $0.payload?[TripActivityEventPayloadKey.rejectionReason] == DiscoveryRejectionReason.rejectedInvalidParticipant.rawValue
            && $0.payload?[TripActivityEventPayloadKey.participantCount] == "1"
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
        let findEventId = UUID().uuidString
        try eventRepo.append(TripActivityEvent(id: findEventId, sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        #expect(viewModel.foundRegions.contains { $0.regionID == "CA" })
        viewModel.removeDiscovery(regionID: "CA")
        #expect(!viewModel.foundRegions.contains { $0.regionID == "CA" })
        let removed = eventRepo.appendedEvents().last { $0.kind == .regionRemoved }
        #expect(removed != nil)
        #expect(removed?.payload?[TripActivityEventPayloadKey.removedDiscoveryEventId] == findEventId)
    }

    @Test func removalArmsCooldownAndImmediateRetapIsBlocked() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let findEventId = UUID().uuidString
        try eventRepo.append(TripActivityEvent(id: findEventId, sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))
        let cooldown = RegionRemovalCooldownService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            regionRemovalCooldownService: cooldown,
            authService: auth
        )

        #expect(viewModel.removeDiscovery(regionID: "CA") == true)
        #expect(viewModel.canSubmitDiscoveryTap(regionID: "CA") == false)
        #expect(viewModel.blockedRetapMessage == nil) // retap hint toast copy disabled; tap still blocked
        #expect(eventRepo.appendedEvents().filter { $0.kind == .regionFound && $0.payload?[TripActivityEventPayloadKey.regionId] == "CA" }.count == 1)
    }

    @Test func tappingDifferentRegionClearsCooldownBlock() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let findEventId = UUID().uuidString
        try eventRepo.append(TripActivityEvent(id: findEventId, sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "CA",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))
        let cooldown = RegionRemovalCooldownService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            regionRemovalCooldownService: cooldown,
            authService: auth
        )

        #expect(viewModel.removeDiscovery(regionID: "CA") == true)
        #expect(viewModel.canSubmitDiscoveryTap(regionID: "CA") == false)
        #expect(viewModel.canSubmitDiscoveryTap(regionID: "NV") == true)
        #expect(viewModel.canSubmitDiscoveryTap(regionID: "CA") == true)
    }

    @Test func submitDiscoveryCollaborativeMultiplayerSecondFinderAppendsAndReplayShowsTwo() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Family",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "user1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId
        game.commonConfig.gameMode = .collaborative

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let lifecycleService = MockTripSessionLifecycleService()
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())

        let auth1 = FirebaseAuthService()
        auth1.currentUser = AppUser(id: "user1", userName: "A", firebaseUID: "user1")
        let vm1 = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            tripActivityEventRecording: recording,
            authService: auth1
        )
        guard case .success = vm1.submitDiscovery(regionID: "us-ca", inputMethod: .list) else {
            Issue.record("Expected first find success")
            return
        }

        let auth2 = FirebaseAuthService()
        auth2.currentUser = AppUser(id: "user2", userName: "B", firebaseUID: "user2")
        let vm2 = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            tripActivityEventRecording: recording,
            authService: auth2
        )
        guard case .success = vm2.submitDiscovery(regionID: "us-ca", inputMethod: .list) else {
            Issue.record("Expected second collaborative find success")
            return
        }

        let discoveries = try eventRepo.discoveries(sessionId: sessionId, gameInstanceId: gameId)
        #expect(discoveries.count == 2)
        #expect(Set(discoveries.map(\.participantId)) == Set(["user1", "user2"]))
        #expect(vm2.foundRegions.contains { $0.regionID == "us-ca" })
    }

    @Test func submitDiscoveryCompetitiveSecondFinderRejectedAndDuplicateListUpdates() async throws {
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
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId
        game.commonConfig.gameMode = .competitive

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(id: "find-1", sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "us-ca",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))

        let lifecycleService = MockTripSessionLifecycleService()
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        let auth2 = FirebaseAuthService()
        auth2.currentUser = AppUser(id: "user2", userName: "B", firebaseUID: "user2")

        let vm2 = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            tripActivityEventRecording: recording,
            authService: auth2
        )

        let result = vm2.submitDiscovery(regionID: "us-ca", inputMethod: .list)
        guard case .rejectedDuplicate = result else {
            Issue.record("Expected rejectedDuplicate for competitive second finder")
            return
        }

        let rejections = eventRepo.appendedEvents().filter { $0.kind == .discoveryRejected }
        #expect(rejections.count == 1)
        #expect(rejections[0].payload?[TripActivityEventPayloadKey.rejectionReason] == DiscoveryRejectionReason.rejectedDuplicate.rawValue)

        let discoveries = try eventRepo.discoveries(sessionId: sessionId, gameInstanceId: gameId)
        #expect(discoveries.count == 1)
        #expect(vm2.myDuplicateRejections.count == 1)
        #expect(vm2.myDuplicateRejections[0].targetId == "us-ca")
    }

    @Test func removeDiscoveryCollaborativeRemovesOnlyCurrentUserFind() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Family",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "user1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        var game = makeGame(sessionId: sessionId, lifecycleState: .started)
        game.id = gameId
        game.commonConfig.gameMode = .collaborative

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        let eventRepo = MockTripActivityEventRepository()
        let id1 = "find-user1"
        let id2 = "find-user2"
        try eventRepo.append(TripActivityEvent(id: id1, sessionId: sessionId, kind: .regionFound, actorId: "user1", payload: [
            TripActivityEventPayloadKey.regionId: "us-ca",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user1",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))
        try eventRepo.append(TripActivityEvent(id: id2, sessionId: sessionId, kind: .regionFound, actorId: "user2", payload: [
            TripActivityEventPayloadKey.regionId: "us-ca",
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: "user2",
            TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
        ]))

        let lifecycleService = MockTripSessionLifecycleService()
        let recording = TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator())
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "A", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: lifecycleService,
            tripActivityEventRecording: recording,
            authService: auth
        )

        #expect(viewModel.foundRegions.contains { $0.regionID == "us-ca" })
        viewModel.removeDiscovery(regionID: "us-ca")

        let discoveries = try eventRepo.discoveries(sessionId: sessionId, gameInstanceId: gameId)
        #expect(discoveries.count == 1)
        #expect(discoveries[0].participantId == "user2")
        #expect(viewModel.foundRegions.contains { $0.regionID == "us-ca" })
        #expect(viewModel.foundRegions.first?.foundBy == "user2")
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
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

    private func makeCanadaProvincesOnlyGame(sessionId: UUID, gameId: UUID) throws -> GameInstance {
        let lpConfig = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.canada.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(
                includeUSTerritories: false,
                includeCanadianTerritories: false,
                includeDC: false
            )
        )
        let payloadData = try JSONEncoder().encode(lpConfig)
        var game = GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig(lifecycleState: .started, configLocked: false, configLockReason: .none),
            gameSpecificPayloadType: GameType.licensePlate.rawValue,
            gameSpecificPayloadVersion: "1",
            gameSpecificPayloadData: payloadData
        )
        return game
    }

    @Test func submitDiscoveryRejectsCanadianTerritoryWhenTerritoriesOff() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        let game = try makeCanadaProvincesOnlyGame(sessionId: sessionId, gameId: gameId)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: eventRepo,
                syncCoordinator: MockSyncCoordinator()
            ),
            authService: auth
        )

        let result = viewModel.submitDiscovery(regionID: "ca-yt", inputMethod: .list)
        guard case .rejectedOutOfScope = result else {
            Issue.record("Expected rejectedOutOfScope, got \(result)")
            return
        }
        #expect(eventRepo.appendedEvents().contains { $0.kind == .regionFound } == false)
        #expect(viewModel.foundRegions.isEmpty)
    }

    @Test func fullClearIgnoresOutOfScopeTerritoriesTowardGoal() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        let game = try makeCanadaProvincesOnlyGame(sessionId: sessionId, gameId: gameId)

        let provinces = ["ca-ab", "ca-bc", "ca-mb", "ca-nb", "ca-nl", "ca-ns", "ca-on", "ca-pe", "ca-qc"]
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        for regionId in provinces {
            try eventRepo.append(TripActivityEvent(
                sessionId: sessionId,
                kind: .regionFound,
                actorId: "user1",
                payload: [
                    TripActivityEventPayloadKey.regionId: regionId,
                    TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                    TripActivityEventPayloadKey.participantId: "user1",
                    TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
                ]
            ))
        }
        // Unscoped would be 10 with territory, but territory is out of scope.
        try eventRepo.append(TripActivityEvent(
            sessionId: sessionId,
            kind: .regionFound,
            actorId: "user1",
            payload: [
                TripActivityEventPayloadKey.regionId: "ca-nt",
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.participantId: "user1",
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue
            ]
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let mockGameLifecycle = MockGameInstanceLifecycleService()
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            gameInstanceLifecycleService: mockGameLifecycle,
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: eventRepo,
                syncCoordinator: MockSyncCoordinator()
            ),
            authService: auth
        )
        viewModel.refreshFoundRegions()

        // Still one province short of goal 10; territory must not complete the game.
        #expect(mockGameLifecycle.markGameFullClearCallCount == 0)

        let result = viewModel.submitDiscovery(regionID: "ca-sk", inputMethod: .list)
        guard case .success = result else {
            Issue.record("Expected success for last province, got \(result)")
            return
        }
        #expect(mockGameLifecycle.markGameFullClearCallCount == 1)
    }

    // MARK: - Step 13.2 fairness watermark + backlog

    private func makeCompetitiveStartedGame(gameId: UUID, sessionId: UUID) -> GameInstance {
        GameInstance(
            id: gameId,
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate"),
            commonConfig: CommonGameConfig(lifecycleState: .started, gameMode: .competitive, configLocked: false, configLockReason: .none)
        )
    }

    private func fairnessLateCompetitivePayload(gameId: UUID, regionId: String, participantId: String, firstFinder: String) -> [String: String] {
        [
            TripActivityEventPayloadKey.regionId: regionId,
            TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
            TripActivityEventPayloadKey.participantId: participantId,
            TripActivityEventPayloadKey.rejectionReason: DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue,
            TripActivityEventPayloadKey.firstFinderParticipantId: firstFinder,
        ]
    }

    /// Solo trip avoids Firebase merge/push in VM init; competitive + `fairnessUiLastAckAt` filters `discovery_rejected` backlog.
    @Test func applyFairnessToastBacklogSkipsRejectionsAtOrBeforeWatermark() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        let tWatermark = Date(timeIntervalSince1970: 200)
        game.fairnessUiLastAckAt = tWatermark

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let tOld = Date(timeIntervalSince1970: 100)
        let tNew = Date(timeIntervalSince1970: 300)
        try eventRepo.append(TripActivityEvent(
            id: "rej-old",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: tOld,
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-wa", participantId: "user1", firstFinder: "user2")
        ))
        try eventRepo.append(TripActivityEvent(
            id: "rej-new",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: tNew,
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-fl", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()

        #expect(viewModel.fairnessToasts.count == 1)
        #expect(viewModel.fairnessToasts[0].message.contains("Florida"))
    }

    @Test func applyFairnessToastBacklogPresentsOldestRejectionFirst() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        let game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()

        try eventRepo.append(TripActivityEvent(
            id: "rej-ca",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 300),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-ca", participantId: "user1", firstFinder: "user2")
        ))
        try eventRepo.append(TripActivityEvent(
            id: "rej-tx",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 100),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-tx", participantId: "user1", firstFinder: "user2")
        ))
        try eventRepo.append(TripActivityEvent(
            id: "rej-ny",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 200),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-ny", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()

        #expect(viewModel.fairnessToasts.count == 3)
        #expect(viewModel.fairnessToasts[0].message.contains("Texas"))
        #expect(viewModel.fairnessToasts[1].message.contains("New York"))
        #expect(viewModel.fairnessToasts[2].message.contains("California"))
    }

    @Test func applyFairnessToastBacklogDoesNotAdvanceWatermarkUntilToastTapAck() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        game.fairnessUiLastAckAt = nil

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        try eventRepo.append(TripActivityEvent(
            id: "rej-a",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: t1,
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-az", participantId: "user1", firstFinder: "user2")
        ))
        try eventRepo.append(TripActivityEvent(
            id: "rej-b",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: t2,
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-nm", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()

        #expect(viewModel.fairnessToasts.count == 2)
        let persisted = try #require(try gameRepo.instance(byId: gameId))
        #expect(persisted.fairnessUiLastAckAt == nil)

        let toastId = try #require(viewModel.fairnessToasts.last?.id)
        viewModel.clearFairnessToast(id: toastId)
        try await Task.sleep(nanoseconds: 100_000_000)

        let persistedAfterAck = try #require(try gameRepo.instance(byId: gameId))
        #expect(persistedAfterAck.fairnessUiLastAckAt == t2)
    }

    @Test func fairnessToastBacklogReshowsOnReenterUntilAck() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        game.fairnessUiLastAckAt = nil

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(
            id: "rej-only",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 1_500),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-or", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")

        let vmFirstEntry = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )
        await vmFirstEntry.applyFairnessToastBacklogFromEventLog()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vmFirstEntry.fairnessToasts.count == 1)

        let vmSecondEntry = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )
        // Init schedules backlog apply asynchronously; wait so we assert after it runs (avoids racing `isApplyingFairnessToastBacklog`).
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vmSecondEntry.fairnessToasts.count == 1)
    }

    @Test func endTripClearsFairnessToasts() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        game.fairnessUiLastAckAt = nil

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(
            id: "rej-end",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 900),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-ut", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()
        #expect(viewModel.fairnessToasts.count == 1)

        try viewModel.endTrip()
        #expect(viewModel.fairnessToasts.isEmpty)
    }

    @Test func deleteTripClearsFairnessToasts() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        game.fairnessUiLastAckAt = nil

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(
            id: "rej-cancel",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 800),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-nv", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()
        #expect(viewModel.fairnessToasts.count == 1)

        try viewModel.deleteTrip()
        #expect(viewModel.fairnessToasts.isEmpty)
    }

    @Test func resetGameClearsFairnessToasts() async throws {
        let sessionId = UUID()
        let gameId = UUID()
        let session = makeSession(id: sessionId, startedAt: Date())
        var game = makeCompetitiveStartedGame(gameId: gameId, sessionId: sessionId)
        game.fairnessUiLastAckAt = nil

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(game)
        let eventRepo = MockTripActivityEventRepository()
        try eventRepo.append(TripActivityEvent(
            id: "rej-reset",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 700),
            actorId: "user1",
            payload: fairnessLateCompetitivePayload(gameId: gameId, regionId: "us-id", participantId: "user1", firstFinder: "user2")
        ))

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "user1", userName: "U", firebaseUID: "user1")
        let mockGameLifecycle = MockGameInstanceLifecycleService()
        let viewModel = LicensePlateGameViewModel(
            session: session,
            game: game,
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            tripActivityEventRepository: eventRepo,
            lifecycleService: MockTripSessionLifecycleService(),
            gameInstanceLifecycleService: mockGameLifecycle,
            tripActivityEventRecording: TripActivityEventRecordingService(tripActivityEventRepository: eventRepo, syncCoordinator: MockSyncCoordinator()),
            authService: auth
        )

        await viewModel.applyFairnessToastBacklogFromEventLog()
        #expect(viewModel.fairnessToasts.count == 1)

        try viewModel.resetGame()
        #expect(viewModel.fairnessToasts.isEmpty)
        #expect(mockGameLifecycle.resetGameCallCount == 1)
    }
}
