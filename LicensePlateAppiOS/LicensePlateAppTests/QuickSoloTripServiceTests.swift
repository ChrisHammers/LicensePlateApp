//
//  QuickSoloTripServiceTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct QuickSoloTripServiceTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func createAndStartQuickSoloTripPersistsActiveSessionAndStartedGame() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let instanceRepo = GameInstanceRepository.shared
        let eventRepo = TripActivityEventRepository.shared
        sessionRepo.setModelContext(ctx)
        instanceRepo.setModelContext(ctx)
        eventRepo.setModelContext(ctx)

        let auth = FirebaseAuthService()
        let userId = "quick-solo-user"
        let testUser = AppUser(id: userId, userName: "Guest", firebaseUID: nil)
        ctx.insert(testUser)
        try ctx.save()
        auth.currentUser = testUser

        let service = QuickSoloTripService(
            tripSessionRepository: sessionRepo,
            gameInstanceRepository: instanceRepo
        )

        let intent = try service.createAndStartQuickSoloTrip(authService: auth)
        let session = try #require(try sessionRepo.session(byId: intent.sessionId))
        #expect(session.status == .active)
        #expect(session.startedAt != nil)

        let games = try instanceRepo.fetchByTripSession(sessionId: intent.sessionId)
        #expect(games.count == 1)
        #expect(games[0].definitionId == GameType.licensePlate.rawValue)
        #expect(games[0].commonConfig.lifecycleState == .started)
        #expect(intent.gameId == games[0].id)
    }
}
