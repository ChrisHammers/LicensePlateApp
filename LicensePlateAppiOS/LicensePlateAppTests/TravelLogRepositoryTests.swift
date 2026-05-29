//
//  TravelLogRepositoryTests.swift
//  LicensePlateAppTests
//
//  Step 03 — TravelLogRepository: fetch completed sessions, summary projections. In-memory SwiftData only.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TravelLogRepositoryTests {

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

    @Test func fetchCompletedSessionsReturnsEndedSessions() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        TripSessionRepository.shared.setModelContext(context)
        GameInstanceRepository.shared.setModelContext(context)
        let repo = TravelLogRepository.shared

        let id1 = UUID().uuidString
        let entity1 = TripSessionEntity(
            id: id1,
            name: "Trip One",
            status: TripSessionState.ended.rawValue,
            createdAt: Date().addingTimeInterval(-200),
            endedAt: Date().addingTimeInterval(-100)
        )
        context.insert(entity1)
        try context.save()

        let sessions = try repo.fetchCompletedSessions(userId: nil, limit: 10)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "Trip One")
        #expect(sessions[0].status == .ended)
        #expect(sessions[0].endedAt != nil)
    }

    @Test func getSummaryProjectionsReturnsTravelLogEntries() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        TripSessionRepository.shared.setModelContext(context)
        GameInstanceRepository.shared.setModelContext(context)
        let repo = TravelLogRepository.shared

        let id1 = UUID().uuidString
        let endedAt = Date().addingTimeInterval(-50)
        let entity1 = TripSessionEntity(
            id: id1,
            name: "Road Trip",
            status: TripSessionState.ended.rawValue,
            createdAt: endedAt.addingTimeInterval(-100),
            endedAt: endedAt
        )
        context.insert(entity1)
        try context.save()

        let entries = try repo.getSummaryProjections(userId: nil, sortBy: .endedAtDesc, limit: 10, statusFilter: .endedOnly)
        #expect(entries.count == 1)
        #expect(entries[0].tripName == "Road Trip")
        #expect(entries[0].sessionId == UUID(uuidString: id1))
        #expect(entries[0].endedAt == endedAt)
        #expect(!entries[0].summary.isEmpty)
    }

    @Test func getSummaryProjectionsSortOrder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        TripSessionRepository.shared.setModelContext(context)
        GameInstanceRepository.shared.setModelContext(context)
        let repo = TravelLogRepository.shared

        let older = Date().addingTimeInterval(-200)
        let newer = Date().addingTimeInterval(-100)
        let entity1 = TripSessionEntity(
            id: UUID().uuidString,
            name: "Older",
            status: TripSessionState.ended.rawValue,
            createdAt: older.addingTimeInterval(-100),
            endedAt: older
        )
        let entity2 = TripSessionEntity(
            id: UUID().uuidString,
            name: "Newer",
            status: TripSessionState.ended.rawValue,
            createdAt: newer.addingTimeInterval(-100),
            endedAt: newer
        )
        context.insert(entity1)
        context.insert(entity2)
        try context.save()

        let desc = try repo.getSummaryProjections(userId: nil, sortBy: .endedAtDesc, limit: 10, statusFilter: .endedOnly)
        #expect(desc.count == 2)
        #expect(desc[0].tripName == "Newer")
        #expect(desc[1].tripName == "Older")

        let asc = try repo.getSummaryProjections(userId: nil, sortBy: .endedAtAsc, limit: 10, statusFilter: .endedOnly)
        #expect(asc.count == 2)
        #expect(asc[0].tripName == "Older")
        #expect(asc[1].tripName == "Newer")
    }

    @Test func getSummaryProjectionsIncludesGameCountFromGameInstanceRepository() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        TripSessionRepository.shared.setModelContext(context)
        GameInstanceRepository.shared.setModelContext(context)
        let repo = TravelLogRepository.shared

        let sessionId = UUID()
        let id1 = sessionId.uuidString
        let endedAt = Date().addingTimeInterval(-50)
        let entity1 = TripSessionEntity(
            id: id1,
            name: "Trip With Games",
            status: TripSessionState.ended.rawValue,
            createdAt: endedAt.addingTimeInterval(-100),
            endedAt: endedAt
        )
        context.insert(entity1)
        let gameEntity = GameInstanceEntity(
            id: UUID().uuidString,
            definitionId: "license_plate",
            sessionId: id1,
            startedAt: Date(),
            ruleSetData: try? JSONEncoder().encode(GameRuleSet(gameDefinitionId: "license_plate"))
        )
        context.insert(gameEntity)
        try context.save()

        let entries = try repo.getSummaryProjections(userId: nil, sortBy: .endedAtDesc, limit: 10, statusFilter: .endedOnly)
        #expect(entries.count == 1)
        #expect(entries[0].tripName == "Trip With Games")
        #expect(entries[0].gameCount == 1)
        #expect(entries[0].summary.contains("1"))
        #expect(entries[0].summary.lowercased().contains("game"))
    }
}
