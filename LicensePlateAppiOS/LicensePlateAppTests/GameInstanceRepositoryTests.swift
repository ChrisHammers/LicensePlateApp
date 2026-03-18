//
//  GameInstanceRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 03 — GameInstanceRepository: create, fetch by trip session, update rule set, save score snapshot.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct GameInstanceRepositoryTests {

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

    @Test func createAndFetchByTripSession() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let sessionId = UUID()
        let ruleSet = GameRuleSet(gameDefinitionId: "license_plate")
        let instance = GameInstance(definitionId: "license_plate", sessionId: sessionId, ruleSet: ruleSet)
        try repo.create(instance: instance)

        let bySession = try repo.fetchByTripSession(sessionId: sessionId)
        #expect(bySession.count == 1)
        #expect(bySession[0].definitionId == "license_plate")
        #expect(bySession[0].sessionId == sessionId)
    }

    @Test func gameCountReturnsZeroWhenEmptyAndCountWhenInstancesExist() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let sessionId = UUID()
        #expect(try repo.gameCount(sessionId: sessionId) == 0)

        let instance = GameInstance(definitionId: "license_plate", sessionId: sessionId, ruleSet: GameRuleSet(gameDefinitionId: "license_plate"))
        try repo.create(instance: instance)
        #expect(try repo.gameCount(sessionId: sessionId) == 1)

        let instance2 = GameInstance(definitionId: "other", sessionId: sessionId, ruleSet: GameRuleSet(gameDefinitionId: "other"))
        try repo.create(instance: instance2)
        #expect(try repo.gameCount(sessionId: sessionId) == 2)
    }

    @Test func deleteForSessionRemovesAllInstancesForSession() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let sessionId = UUID()
        let instance = GameInstance(definitionId: "license_plate", sessionId: sessionId, ruleSet: GameRuleSet(gameDefinitionId: "license_plate"))
        try repo.create(instance: instance)
        #expect(try repo.fetchByTripSession(sessionId: sessionId).count == 1)
        #expect(try repo.gameCount(sessionId: sessionId) == 1)

        try repo.deleteForSession(sessionId: sessionId)
        #expect(try repo.fetchByTripSession(sessionId: sessionId).isEmpty)
        #expect(try repo.gameCount(sessionId: sessionId) == 0)
    }

    @Test func instanceByIdReturnsNilWhenMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let result = try repo.instance(byId: UUID())
        #expect(result == nil)
    }

    @Test func updateRuleSetPersists() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let ruleSet = GameRuleSet(gameDefinitionId: "license_plate")
        let instance = GameInstance(definitionId: "license_plate", sessionId: UUID(), ruleSet: ruleSet)
        try repo.create(instance: instance)
        let id = instance.id

        let updatedRuleSet = GameRuleSet(gameDefinitionId: "license_plate", payload: ["scoring": "points"])
        try repo.updateRuleSet(instanceId: id, ruleSet: updatedRuleSet)

        let loaded = try repo.instance(byId: id)
        #expect(loaded != nil)
        #expect(loaded?.ruleSet.gameDefinitionId == "license_plate")
        #expect(loaded?.ruleSet.payload?["scoring"] == "points")
    }

    @Test func saveScoreSnapshotPersists() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let instance = GameInstance(
            definitionId: "license_plate",
            sessionId: UUID(),
            ruleSet: GameRuleSet(gameDefinitionId: "license_plate")
        )
        try repo.create(instance: instance)
        let id = instance.id

        let snapshot = try JSONEncoder().encode(["score": "100"])
        try repo.saveScoreSnapshot(instanceId: id, snapshot: snapshot)

        let descriptor = FetchDescriptor<GameScoreSnapshotEntity>(
            predicate: #Predicate<GameScoreSnapshotEntity> { $0.gameInstanceId == id.uuidString }
        )
        let entities = try context.fetch(descriptor)
        #expect(entities.count == 1)
        #expect(entities[0].snapshotData == snapshot)
        let decoded = try JSONDecoder().decode([String: String].self, from: entities[0].snapshotData)
        #expect(decoded["score"] == "100")
    }

    /// Step 05 — Failure: update throws instanceNotFound when instance was never created.
    @Test func updateThrowsInstanceNotFoundWhenInstanceMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = GameInstanceRepository.shared
        repo.setModelContext(context)

        let unknownId = UUID()
        let sessionId = UUID()
        let ruleSet = GameRuleSet(gameDefinitionId: "license_plate")
        let instance = GameInstance(id: unknownId, definitionId: "license_plate", sessionId: sessionId, ruleSet: ruleSet)
        do {
            try repo.update(instance: instance)
            #expect(Bool(false), "Expected GameInstanceRepositoryError.instanceNotFound")
        } catch let error as GameInstanceRepositoryError {
            if case .instanceNotFound(let id) = error {
                #expect(id == unknownId)
            } else {
                #expect(Bool(false), "Expected instanceNotFound, got \(error)")
            }
        }
    }
}
