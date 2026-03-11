//
//  GameLifecycleStateAndConfigLockTests.swift
//  LicensePlateAppTests
//
//  Step 07.5 — Configuration locking when game transitions to started.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct GameLifecycleStateAndConfigLockTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
    }

    @Test func transitionGamesToStartedSetsLifecycleAndLock() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let sessionId = UUID()
        let instance = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: sessionId,
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            commonConfig: CommonGameConfig(lifecycleState: .created, configLocked: false, configLockReason: .none)
        )
        try repo.create(instance: instance)

        try repo.transitionGamesToStarted(sessionId: sessionId)

        let loaded = try repo.fetchByTripSession(sessionId: sessionId)
        #expect(loaded.count == 1)
        #expect(loaded[0].commonConfig.lifecycleState == .started)
        #expect(loaded[0].commonConfig.configLocked == true)
        #expect(loaded[0].commonConfig.configLockReason == .gameStarted)
    }

    @Test func createdGameHasDefaultConfigUnlocked() async throws {
        let config = CommonGameConfig()
        #expect(config.lifecycleState == .created)
        #expect(config.configLocked == false)
        #expect(config.configLockReason == .none)
    }
}
