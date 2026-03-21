//
//  TripSetupSemanticsTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.4 — Trip-level setup: TripMode and roster container; no per-game rules on TripSession.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSetupSemanticsTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func multiplayerTripWithSingleParticipantIsValid() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "solo-but-mp-trip"
        let testUser = AppUser(id: userId, userName: "T", firebaseUID: userId)
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
        viewModel.tripParticipationMode = .multiplayer

        let session = try viewModel.createTrip()
        #expect(session.mode == .multiplayer)
        #expect(session.participants.count == 1)
    }
}
