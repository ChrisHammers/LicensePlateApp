//
//  SchemaMigrationGameplayTests.swift
//  LicensePlateAppTests
//
//  Step 02 — schema V4 and new gameplay entities: container creation, insert/fetch, migration defaults.
//  Tests only new schema and new entities; no tests for legacy Trip data loading.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

struct SchemaMigrationGameplayTests {

    /// In-memory container with versioned schema and migration plan (no production store).
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

    @Test func containerCreatesWithVersionedSchemaAndMigrationPlan() async throws {
        let container = try makeContainer()
        #expect(container != nil)
    }

    @Test func insertAndFetchTripSessionEntity() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID().uuidString
        let name = "Test Session"
        let entity = TripSessionEntity(
            id: id,
            name: name,
            status: TripSessionState.active.rawValue,
            createdAt: Date()
        )
        context.insert(entity)
        try context.save()

        let descriptor = FetchDescriptor<TripSessionEntity>(predicate: #Predicate { $0.id == id })
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].name == name)
        #expect(results[0].status == TripSessionState.active.rawValue)
    }

    @Test func insertAndFetchGameInstanceEntity() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID().uuidString
        let sessionId = UUID().uuidString
        let startedAt = Date()
        let entity = GameInstanceEntity(
            id: id,
            definitionId: "license_plate",
            sessionId: sessionId,
            startedAt: startedAt
        )
        context.insert(entity)
        try context.save()

        let descriptor = FetchDescriptor<GameInstanceEntity>(predicate: #Predicate { $0.id == id })
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].definitionId == "license_plate")
        #expect(results[0].sessionId == sessionId)
        #expect(results[0].endedAt == nil)
    }

    @Test func tripSessionEntityMigrationDefaultsSane() async throws {
        let entity = TripSessionEntity(
            id: UUID().uuidString,
            name: "Defaults",
            status: TripSessionState.active.rawValue,
            createdAt: Date()
        )
        #expect(entity.createdBy == nil)
        #expect(entity.startedAt == nil)
        #expect(entity.endedAt == nil)
        #expect(entity.participantsData == nil)
    }

    @Test func gameInstanceEntityRoundTripsWithRuleSetData() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ruleSet = GameRuleSet(gameDefinitionId: "license_plate")
        let ruleSetData = try JSONEncoder().encode(ruleSet)
        let id = UUID().uuidString
        let sessionId = UUID().uuidString
        let entity = GameInstanceEntity(
            id: id,
            definitionId: "license_plate",
            sessionId: sessionId,
            startedAt: Date(),
            ruleSetData: ruleSetData
        )
        context.insert(entity)
        try context.save()

        let descriptor = FetchDescriptor<GameInstanceEntity>(predicate: #Predicate { $0.id == id })
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        let fetched = results[0]
        #expect(fetched.ruleSetData != nil)
        let decoded = try JSONDecoder().decode(GameRuleSet.self, from: fetched.ruleSetData!)
        #expect(decoded.gameDefinitionId == "license_plate")
    }

    @Test func insertAndFetchUserAchievementEntity() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let entity = UserAchievementEntity(
            userId: "user-1",
            achievementId: "first_win",
            unlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastProgress: 1,
            isBackfilled: false
        )
        context.insert(entity)
        try context.save()

        let key = UserAchievementEntity.makeRecordKey(userId: "user-1", achievementId: "first_win")
        let descriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.recordKey == key }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].lastProgress == 1)
        #expect(results[0].isBackfilled == false)
    }

    @Test func migrateV19ToV20PreservesDataAndAllowsUserAchievements() async throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-v19-v20-\(UUID().uuidString).store")

        let v19Schema = Schema(versionedSchema: SchemaVersion19.self)
        let v19Config = ModelConfiguration(schema: v19Schema, url: storeURL)
        let v19Container = try ModelContainer(
            for: v19Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [v19Config]
        )

        let sessionId = UUID().uuidString
        let v19Context = ModelContext(v19Container)
        v19Context.insert(
            TripSessionEntity(
                id: sessionId,
                name: "Pre-V20 Trip",
                status: TripSessionState.active.rawValue,
                createdAt: Date()
            )
        )
        try v19Context.save()

        let v20Schema = Schema(versionedSchema: SchemaVersion20.self)
        let v20Config = ModelConfiguration(schema: v20Schema, url: storeURL)
        let v20Container = try ModelContainer(
            for: v20Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [v20Config]
        )

        let v20Context = ModelContext(v20Container)
        let tripDescriptor = FetchDescriptor<TripSessionEntity>(
            predicate: #Predicate<TripSessionEntity> { $0.id == sessionId }
        )
        let trips = try v20Context.fetch(tripDescriptor)
        #expect(trips.count == 1)
        #expect(trips[0].name == "Pre-V20 Trip")

        v20Context.insert(
            UserAchievementEntity(
                userId: "user-1",
                achievementId: "first_win",
                unlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastProgress: 1,
                isBackfilled: false
            )
        )
        try v20Context.save()

        let achievementKey = UserAchievementEntity.makeRecordKey(userId: "user-1", achievementId: "first_win")
        let achievementDescriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.recordKey == achievementKey }
        )
        let achievements = try v20Context.fetch(achievementDescriptor)
        #expect(achievements.count == 1)
    }
}
