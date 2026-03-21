//
//  MultiGameTripCreationTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.4 — One TripSession can host multiple GameInstances; trip mode stays solo/multiplayer only.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct MultiGameTripCreationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func oneTripSessionTwoGameInstancesPersisted() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let sessionRepo = TripSessionRepository.shared
        let gameRepo = GameInstanceRepository.shared
        sessionRepo.setModelContext(ctx)
        gameRepo.setModelContext(ctx)

        let sessionId = UUID()
        let created = Date()
        let session = TripSession(
            id: sessionId,
            name: "Multi-game",
            status: .created,
            mode: .solo,
            createdAt: created,
            createdBy: "owner",
            startedAt: nil,
            endedAt: nil,
            endedBy: nil,
            participants: [TripParticipant(userId: "owner", role: .owner, joinedAt: created)]
        )
        try sessionRepo.create(session: session)

        let startedAt = Date()
        let commonLP = CommonGameConfig(lifecycleState: .created, gameMode: .collaborative)
        let lpGame = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: nil,
            ruleSet: GameType.licensePlate.defaultRuleSet(),
            commonConfig: commonLP
        )
        let commonRS = CommonGameConfig(lifecycleState: .created, gameMode: .collaborative)
        let rsGame = GameInstance(
            definitionId: GameType.roadSignBingo.rawValue,
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: nil,
            ruleSet: GameType.roadSignBingo.defaultRuleSet(),
            commonConfig: commonRS
        )
        try gameRepo.create(instance: lpGame)
        try gameRepo.create(instance: rsGame)

        let loaded = try gameRepo.fetchByTripSession(sessionId: sessionId)
        #expect(loaded.count == 2)
        let types = Set(loaded.map(\.definitionId))
        #expect(types.contains(GameType.licensePlate.rawValue))
        #expect(types.contains(GameType.roadSignBingo.rawValue))

        let reloadedSession = try sessionRepo.session(byId: sessionId)
        #expect(reloadedSession?.mode == .solo)
    }

    @Test func tripModeHasNoCombinedValueForMultiGame() async throws {
        let all = TripMode.allCases.map(\.rawValue)
        #expect(all.contains("solo"))
        #expect(all.contains("multiplayer"))
        #expect(!all.contains { $0 == "combined" })
    }
}
