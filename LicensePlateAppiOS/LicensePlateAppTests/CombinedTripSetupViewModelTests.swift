//
//  CombinedTripSetupViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 06 — CombinedTripSetupViewModel: create TripSession + GameInstances (canonical only).
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct CombinedTripSetupViewModelTests {

    private final class StubNewTripDefaultsStore: NewTripDefaultsStoring {
        private let snapshot: NewTripDefaults

        init(snapshot: NewTripDefaults) {
            self.snapshot = snapshot
        }

        func load() -> NewTripDefaults {
            snapshot
        }

        func save(_ snapshot: NewTripDefaults) {}
    }

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

    @Test func initAppliesNewTripDefaults() async throws {
        let auth = FirebaseAuthService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth,
            newTripDefaultsStore: StubNewTripDefaultsStore(snapshot: makeDefaults(startTripRightAway: true))
        )

        #expect(viewModel.includeUS == true)
        #expect(viewModel.includeCanada == false)
        #expect(viewModel.includeMexico == true)
        #expect(viewModel.startTripRightAway == true)
        #expect(viewModel.skipVoiceConfirmation == true)
        #expect(viewModel.holdToTalk == false)
        #expect(viewModel.saveLocationWhenMarkingPlates == false)
        #expect(viewModel.showMyLocationOnLargeMap == false)
        #expect(viewModel.trackMyLocationDuringTrip == false)
        #expect(viewModel.showMyActiveTripOnLargeMap == false)
        #expect(viewModel.showMyActiveTripOnSmallMap == false)
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
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.tripName = "My Trip"
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.includeCanada = false
        viewModel.includeMexico = false

        let session = try viewModel.createTrip()

        #expect(session.name == "My Trip")
        #expect(session.createdBy == userId)
        #expect(session.status == .created)
        #expect(session.startedAt == nil)

        let loadedSession = try sessionRepo.session(byId: session.id)
        #expect(loadedSession != nil)
        #expect(loadedSession?.id == session.id)
        #expect(loadedSession?.name == "My Trip")
        #expect(loadedSession?.status == .created)
        #expect(loadedSession?.startedAt == nil)

        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        #expect(instances.count == 1)
        #expect(instances[0].definitionId == GameType.licensePlate.rawValue)
        #expect(instances[0].licensePlateConfig()?.selectedCountries == [.unitedStates])
        #expect(session.mode == .solo)
        #expect(session.participants.count == 1)
        #expect(session.participants[0].role == .owner)
    }

    @Test func createTripUsesDateNameWhenNameEmpty() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        let eventRepo = TripActivityEventRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)
        eventRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.tripName = ""
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let session = try viewModel.createTrip()

        #expect(!session.name.isEmpty)
        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        #expect(instances.count == 1)
    }

    @Test func canCreateRequiresAtLeastOneGameType() async throws {
        let auth = FirebaseAuthService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        #expect(viewModel.canCreate == true)

        viewModel.selectedGameTypes = []
        #expect(viewModel.canCreate == false)
    }

    @Test func createTripThrowsWhenNoCountries() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.tripName = "Trip"
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = false
        viewModel.includeCanada = false
        viewModel.includeMexico = false

        #expect(throws: CombinedTripSetupError.self) {
            _ = try viewModel.createTrip()
        }
    }

    @Test func countryValidationMessageShownWhenNoCountriesSelected() async throws {
        let auth = FirebaseAuthService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth
        )
        viewModel.includeUS = false
        viewModel.includeCanada = false
        viewModel.includeMexico = false
        #expect(viewModel.countryValidationMessage == "Select at least one country.".localized)
        #expect(viewModel.canCreate == false)
    }

    @Test func toggleGameTypeAddsAndRemoves() async throws {
        let auth = FirebaseAuthService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: TripSessionRepository.shared,
            gameInstanceRepository: GameInstanceRepository.shared,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]

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
        let eventRepo = TripActivityEventRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)
        eventRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "test-user"
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let mockLifecycle = MockTripSessionLifecycleService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            lifecycleService: mockLifecycle,
            authService: auth
        )
        viewModel.tripName = "My Trip"
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.startTripRightAway = true

        let session = try viewModel.createTrip()

        #expect(mockLifecycle.startTripCallCount == 1)
        #expect(mockLifecycle.startTripSessionIds.first == session.id)
        #expect(mockLifecycle.startTripActorIds.first == userId)
    }

    @Test func createTripUsesDefaultStartRightAwaySetting() async throws {
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
        let testUser = AppUser(id: userId, userName: "Test", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let mockLifecycle = MockTripSessionLifecycleService()
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            lifecycleService: mockLifecycle,
            authService: auth,
            newTripDefaultsStore: StubNewTripDefaultsStore(snapshot: makeDefaults(startTripRightAway: true))
        )
        viewModel.tripName = "My Trip"
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let session = try viewModel.createTrip()

        #expect(viewModel.startTripRightAway == true)
        #expect(mockLifecycle.startTripCallCount == 1)
        #expect(mockLifecycle.startTripSessionIds.first == session.id)
        #expect(mockLifecycle.startTripActorIds.first == userId)
    }

    @Test func createTripPersistsTerritoryOptionsFromSetupToggles() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        let eventRepo = TripActivityEventRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)
        eventRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.includeCanada = false
        viewModel.includeMexico = false
        viewModel.includeUSTerritories = false
        viewModel.includeDC = true
        viewModel.includeCanadianTerritories = true

        let session = try viewModel.createTrip()

        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        let decoded = instances[0].licensePlateConfig()
        #expect(decoded?.territoryOptions.includeUSTerritories == false)
        #expect(decoded?.territoryOptions.includeDC == true)
        #expect(decoded?.territoryOptions.includeCanadianTerritories == false)
    }

    @Test func createTripNormalizesTerritoryWhenUSDeselected() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u2", userName: "U", firebaseUID: "u2")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = false
        viewModel.includeCanada = true
        viewModel.includeMexico = false
        viewModel.includeUSTerritories = true
        viewModel.includeDC = true
        viewModel.includeCanadianTerritories = true

        let session = try viewModel.createTrip()
        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        let opts = instances[0].licensePlateConfig()?.territoryOptions
        #expect(opts?.includeUSTerritories == false)
        #expect(opts?.includeDC == false)
        #expect(opts?.includeCanadianTerritories == true)
    }

    @Test func createTripDerivedParticipationSoloWithOneParticipant() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u-mp", userName: "U", firebaseUID: "u-mp")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let session = try viewModel.createTrip()
        #expect(session.mode == .solo)
        #expect(session.participants.count == 1)
    }

    @Test func createTripPersistsCompetitiveGameMode() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let testUser = AppUser(id: "u-cmp", userName: "U", firebaseUID: "u-cmp")
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true
        viewModel.defaultGameMode = .competitive

        let session = try viewModel.createTrip()
        let instances = try instanceRepo.fetchByTripSession(sessionId: session.id)
        #expect(instances.count == 1)
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
        let testUser = AppUser(id: userId, userName: "U", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        try sessionRepo.create(session: TripSession(
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
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            tripEntitlementGate: gate,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        #expect(throws: TripEntitlementGateError.self) {
            _ = try viewModel.createTrip()
        }
        #expect(viewModel.shouldPresentTripLimitPaywall)
        let activeSessions = try sessionRepo.loadActiveSessions(userId: userId)
        #expect(activeSessions.count == 1)
    }

    @Test func createTripAllowsGoldThirdActiveTripAndBlocksFourth() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "gold-user"
        let testUser = AppUser(id: userId, userName: "Gold", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        for index in 1...2 {
            try sessionRepo.create(session: TripSession(
                id: UUID(),
                name: "Existing \(index)",
                status: .active,
                createdAt: Date(),
                createdBy: userId,
                startedAt: Date(),
                participants: [TripParticipant(userId: userId, role: .owner, joinedAt: Date())]
            ))
        }

        let bridge = MockRevenueCatBridge(tier: .gold)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            tripEntitlementGate: gate,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        _ = try viewModel.createTrip()
        #expect(viewModel.shouldPresentTripLimitPaywall == false)

        #expect(throws: TripEntitlementGateError.self) {
            _ = try viewModel.createTrip()
        }
        #expect(viewModel.shouldPresentTripLimitPaywall)
    }

    @Test func createTripAllowsRoyaleBeyondGoldLimit() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "royale-user"
        let testUser = AppUser(id: userId, userName: "Royale", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        for index in 1...4 {
            try sessionRepo.create(session: TripSession(
                id: UUID(),
                name: "Existing \(index)",
                status: .active,
                createdAt: Date(),
                createdBy: userId,
                startedAt: Date(),
                participants: [TripParticipant(userId: userId, role: .owner, joinedAt: Date())]
            ))
        }

        let bridge = MockRevenueCatBridge(tier: .royale)
        let entitlementService = EntitlementService(revenueCatBridge: bridge)
        entitlementService.setCurrentUserId(userId)
        let gate = TripEntitlementGate(
            tripSessionRepository: sessionRepo,
            entitlementService: entitlementService,
            analytics: AnalyticsLoggingSpy()
        )
        let viewModel = CombinedTripSetupViewModel(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            tripEntitlementGate: gate,
            authService: auth
        )
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        _ = try viewModel.createTrip()

        #expect(viewModel.shouldPresentTripLimitPaywall == false)
    }
}
