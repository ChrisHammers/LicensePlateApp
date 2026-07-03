//
//  GameSetupViewModelTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct GameSetupViewModelTests {

    private final class StubNewTripDefaultsStore: NewTripDefaultsStoring {
        private let snapshot: NewTripDefaults
        init(snapshot: NewTripDefaults) { self.snapshot = snapshot }
        func load() -> NewTripDefaults { snapshot }
        func save(_ snapshot: NewTripDefaults) {}
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    private func makeDefaults(startTripRightAway: Bool) -> NewTripDefaults {
        NewTripDefaults(
            includeUS: true,
            includeCanada: false,
            includeMexico: true,
            startTripRightAway: startTripRightAway,
            skipVoiceConfirmation: true,
            holdToTalk: false,
            saveLocationWhenMarkingPlates: false,
            showMyLocationOnLargeMap: false,
            trackMyLocationDuringTrip: false,
            showMyActiveTripOnLargeMap: false,
            showMyActiveTripOnSmallMap: false
        )
    }

    private func makeDraft(
        tripName: String = "",
        startTripRightAway: Bool = false,
        selectedPassengerIds: Set<String> = []
    ) -> TripSetupDraft {
        TripSetupDraft(
            tripName: tripName,
            selectedPassengerIds: selectedPassengerIds,
            startTripRightAway: startTripRightAway,
            skipVoiceConfirmation: false,
            holdToTalk: true,
            saveLocationWhenMarkingPlates: true,
            showMyLocationOnLargeMap: true,
            trackMyLocationDuringTrip: true,
            showMyActiveTripOnLargeMap: true,
            showMyActiveTripOnSmallMap: true
        )
    }

    private func makeNewTripViewModel(
        draft: TripSetupDraft,
        sessionRepo: TripSessionRepositoryProtocol,
        instanceRepo: GameInstanceRepositoryProtocol,
        auth: FirebaseAuthService,
        lifecycleService: TripSessionLifecycleServiceProtocol = TripSessionLifecycleService.shared,
        tripEntitlementGate: TripEntitlementGate = .shared,
        newTripDefaultsStore: NewTripDefaultsStoring = UserDefaultsNewTripDefaultsStore()
    ) -> GameSetupViewModel {
        GameSetupViewModel(
            context: .newTrip(draft),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            lifecycleService: lifecycleService,
            tripEntitlementGate: tripEntitlementGate,
            authService: auth,
            newTripDefaultsStore: newTripDefaultsStore
        )
    }

    private func creatorAuth(userId: String = "user1") -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: userId, userName: "User", firebaseUID: userId)
        return auth
    }

    private func licensePlateInstance(sessionId: UUID, lifecycle: GameInstanceState, countries: [PlateRegion.Country]? = nil) -> GameInstance {
        var g = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: CommonGameConfig(lifecycleState: lifecycle, gameMode: .collaborative)
        )
        g.id = UUID()
        if let countries {
            let config = LicensePlateGameConfig(selectedCountriesRawValues: countries.map(\.rawValue))
            g.gameSpecificPayloadType = GameType.licensePlate.rawValue
            g.gameSpecificPayloadVersion = "1"
            g.gameSpecificPayloadData = try? JSONEncoder().encode(config)
        }
        return g
    }

    @Test func usesGameDefaultOptions_whenScopeMatchesStoredDefaults() async throws {
        let store = StubNewTripDefaultsStore(snapshot: makeDefaults(startTripRightAway: false))
        let auth = FirebaseAuthService()
        let viewModel = GameSetupViewModel(
            context: .newTrip(makeDraft()),
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth,
            newTripDefaultsStore: store
        )
        #expect(viewModel.usesGameDefaultOptions == true)

        viewModel.includeDC = false
        #expect(viewModel.usesGameDefaultOptions == false)
    }

    @Test func createTripWithDefaultConfigPersistsSessionAndGameInstances() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        let eventRepo = TripActivityEventRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)
        eventRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "test-user"
        auth.currentUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let draft = makeDraft(tripName: "My Trip")
        let viewModel = makeNewTripViewModel(draft: draft, sessionRepo: sessionRepo, instanceRepo: instanceRepo, auth: auth)
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.includeCanada = false
        viewModel.includeMexico = false

        let session = try viewModel.createTrip()

        #expect(session.name == "My Trip")
        #expect(session.createdBy == userId)
        #expect(session.status == .created)
        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        #expect(instances.count == 1)
        #expect(instances[0].licensePlateConfig()?.selectedCountries == [.unitedStates])
        #expect(session.mode == .solo)
    }

    @Test func createTripUsesDateNameWhenNameEmpty() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let viewModel = makeNewTripViewModel(
            draft: makeDraft(),
            sessionRepo: sessionRepo,
            instanceRepo: instanceRepo,
            auth: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let session = try viewModel.createTrip()
        #expect(!session.name.isEmpty)
    }

    @Test func canConfirmRequiresAtLeastOneGameType() async throws {
        let auth = FirebaseAuthService()
        let viewModel = makeNewTripViewModel(
            draft: makeDraft(),
            sessionRepo: TripSessionRepository.shared,
            instanceRepo: GameInstanceRepository.shared,
            auth: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        #expect(viewModel.canConfirm == true)
        viewModel.selectedGameTypes = []
        #expect(viewModel.canConfirm == false)
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = false
        viewModel.includeCanada = false
        viewModel.includeMexico = false
        #expect(viewModel.canConfirm == false)
    }

    @Test func createTripThrowsWhenNoGameTypes() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let viewModel = makeNewTripViewModel(
            draft: makeDraft(tripName: "Trip"),
            sessionRepo: sessionRepo,
            instanceRepo: instanceRepo,
            auth: auth
        )
        viewModel.selectedGameTypes = []

        #expect(throws: CombinedTripSetupError.self) {
            _ = try viewModel.createTrip()
        }
    }

    @Test func toggleGameTypeAddsAndRemoves() async throws {
        let auth = FirebaseAuthService()
        let viewModel = makeNewTripViewModel(
            draft: makeDraft(),
            sessionRepo: TripSessionRepository.shared,
            instanceRepo: GameInstanceRepository.shared,
            auth: auth
        )
        viewModel.toggleGameType(.licensePlate)
        #expect(!viewModel.selectedGameTypes.contains(.licensePlate))
        viewModel.toggleGameType(.licensePlate)
        #expect(viewModel.selectedGameTypes.contains(.licensePlate))
    }

    @Test func createTripWithStartRightAwayCallsLifecycleServiceStartTrip() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "test-user"
        auth.currentUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let mockLifecycle = MockTripSessionLifecycleService()
        let viewModel = makeNewTripViewModel(
            draft: makeDraft(tripName: "My Trip", startTripRightAway: true),
            sessionRepo: sessionRepo,
            instanceRepo: instanceRepo,
            auth: auth,
            lifecycleService: mockLifecycle
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let session = try viewModel.createTrip()
        #expect(mockLifecycle.startTripCallCount == 1)
        #expect(mockLifecycle.startTripSessionIds.first == session.id)
    }

    @Test func createTripPersistsTerritoryOptionsFromGameSetup() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let viewModel = makeNewTripViewModel(draft: makeDraft(), sessionRepo: sessionRepo, instanceRepo: instanceRepo, auth: auth)
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.includeCanada = false
        viewModel.includeMexico = false
        viewModel.includeUSTerritories = false
        viewModel.includeDC = true
        viewModel.includeCanadianTerritories = true

        let session = try viewModel.createTrip()
        let opts = try instanceRepo.fetchByTripSession(sessionId: session.id)[0].licensePlateConfig()?.territoryOptions
        #expect(opts?.includeUSTerritories == false)
        #expect(opts?.includeDC == true)
        #expect(opts?.includeCanadianTerritories == false)
    }

    @Test func createTripPersistsCompetitiveGameMode() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u-cmp", userName: "U", firebaseUID: "u-cmp")
        ctx.insert(auth.currentUser!)
        try ctx.save()

        let viewModel = makeNewTripViewModel(
            draft: makeDraft(),
            sessionRepo: sessionRepo,
            instanceRepo: instanceRepo,
            auth: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.defaultGameMode = .competitive

        let session = try viewModel.createTrip()
        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        #expect(instances[0].commonConfig.gameMode == .competitive)
    }

    @Test func createTripBlockedWhenSignedUpUserAtActiveTripLimit() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "limit-user"
        auth.currentUser = AppUser(id: userId, userName: "U", firebaseUID: userId)
        ctx.insert(auth.currentUser!)
        try ctx.save()

        try sessionRepo.create(session: TripSession(
            id: UUID(),
            name: "Existing",
            status: .created,
            createdAt: Date(),
            createdBy: userId,
            participants: [TripParticipant(userId: userId, role: .owner, joinedAt: Date())]
        ))

        let entitlementService = EntitlementService(revenueCatBridge: MockRevenueCatBridge(tier: .guest))
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )
        let viewModel = makeNewTripViewModel(
            draft: makeDraft(),
            sessionRepo: sessionRepo,
            instanceRepo: instanceRepo,
            auth: auth,
            tripEntitlementGate: gate
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        #expect(throws: TripEntitlementGateError.self) {
            _ = try viewModel.createTrip()
        }
        #expect(viewModel.shouldPresentTripLimitPaywall)
    }

    // MARK: - addGame

    @Test func addGame_whenCreatedTripAndOneLP_rejectsSecondLPWhileFirstIsCreated() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Created Trip",
            status: .created,
            createdAt: Date(),
            createdBy: "user1",
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .created)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)

        let viewModel = GameSetupViewModel(
            context: .addToExistingTrip(sessionId: sessionId),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            authService: creatorAuth()
        )

        #expect(throws: CombinedTripSetupError.self) {
            _ = try viewModel.addGame()
        }
        #expect(try gameRepo.fetchByTripSession(sessionId: sessionId).count == 1)
    }

    @Test func addGame_whenPriorLPEnded_addsSecondLPAndStartsOnActiveTrip() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Active",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        let endedLP = licensePlateInstance(sessionId: sessionId, lifecycle: .ended, countries: [.unitedStates, .canada])

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(endedLP)
        let gameLifecycle = MockGameInstanceLifecycleService()

        let viewModel = GameSetupViewModel(
            context: .addToExistingTrip(sessionId: sessionId),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            gameInstanceLifecycleService: gameLifecycle,
            authService: creatorAuth()
        )
        viewModel.includeUS = true
        viewModel.includeMexico = true
        viewModel.includeCanada = false

        _ = try viewModel.addGame()

        let games = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(games.count == 2)
        #expect(gameLifecycle.startGameCallCount == 1)
        let added = games.first { $0.commonConfig.lifecycleState == .created || $0.id != endedLP.id }
        let config = games.last?.licensePlateConfig()
        #expect(config?.selectedCountries == [.unitedStates, .mexico])
    }

    @Test func addGame_usesSelectedScope_notOnlyTemplate() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Active",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        let endedLP = licensePlateInstance(sessionId: sessionId, lifecycle: .ended, countries: [.unitedStates])

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(endedLP)

        let viewModel = GameSetupViewModel(
            context: .addToExistingTrip(sessionId: sessionId),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            authService: creatorAuth()
        )
        viewModel.includeUS = false
        viewModel.includeCanada = true
        viewModel.includeMexico = false

        _ = try viewModel.addGame()

        let newGame = try gameRepo.fetchByTripSession(sessionId: sessionId).last
        #expect(newGame?.licensePlateConfig()?.selectedCountries == [.canada])
    }

    @Test func addGame_whenPassenger_throwsNotTripCreator() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Multi Trip",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "user2", role: .member, joinedAt: Date())
            ]
        )
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .ended)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)

        let viewModel = GameSetupViewModel(
            context: .addToExistingTrip(sessionId: sessionId),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            authService: creatorAuth(userId: "user2")
        )

        #expect(throws: CombinedTripSetupError.self) {
            _ = try viewModel.addGame()
        }
        #expect(try gameRepo.fetchByTripSession(sessionId: sessionId).count == 1)
    }

    @Test func addGame_whenTripEnded_throwsTripTerminal() async throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Over",
            status: .ended,
            createdAt: Date(),
            createdBy: "user1",
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        let lp = licensePlateInstance(sessionId: sessionId, lifecycle: .ended)

        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let gameRepo = MockGameInstanceRepository()
        gameRepo.seed(lp)

        let viewModel = GameSetupViewModel(
            context: .addToExistingTrip(sessionId: sessionId),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: gameRepo,
            authService: creatorAuth()
        )

        #expect(throws: CombinedTripSetupError.self) {
            _ = try viewModel.addGame()
        }
    }
}
