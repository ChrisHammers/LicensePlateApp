//
//  CombinedTripSetupViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 06 — CombinedTripSetupViewModel: create TripSession + GameInstances + legacy Trip.
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

    @Test func createTripWithDefaultConfigPersistsSessionAndLegacyTrip() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

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

        let trip = try viewModel.createTrip(modelContext: ctx)

        #expect(trip.name == "My Trip")
        #expect(trip.foundRegions.isEmpty)
        #expect(trip.enabledCountries == [.unitedStates])
        #expect(trip.createdBy == userId)

        let session = try sessionRepo.session(byId: trip.id)
        #expect(session != nil)
        #expect(session?.id == trip.id)
        #expect(session?.name == "My Trip")

        let instances = try instanceRepo.fetchByTripSession(sessionId: trip.id)
        #expect(instances.count == 1)
        #expect(instances[0].definitionId == GameType.licensePlate.rawValue)
    }

    @Test func createTripUsesDateNameWhenNameEmpty() async throws {
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
        viewModel.tripName = ""
        viewModel.selectedGameTypes = [.licensePlate]
        viewModel.includeUS = true

        let trip = try viewModel.createTrip(modelContext: ctx)

        #expect(!trip.name.isEmpty)
        #expect(trip.foundRegions.isEmpty)
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
            _ = try viewModel.createTrip(modelContext: ctx)
        }
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
}
