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
}
