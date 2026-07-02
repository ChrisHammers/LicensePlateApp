//
//  TripSetupSemanticsTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.4 / 6.10 — Trip roster from setup; participation derived from participant count.
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

    @Test func newTripWithSingleParticipantIsSoloDerived() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "creator-only"
        let testUser = AppUser(id: userId, userName: "T", firebaseUID: userId)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let tripSetup = TripSetupViewModel(authService: auth)
        tripSetup.includeUS = true
        let draft = tripSetup.buildDraft()

        let gameSetup = GameSetupViewModel(
            context: .newTrip(draft),
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo,
            authService: auth
        )
        gameSetup.selectedGameTypes = [.licensePlate]

        let session = try gameSetup.createTrip()
        #expect(session.mode == .solo)
        #expect(session.participants.count == 1)
    }
}
