//
//  DiscoveryResolutionRepositoryTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct DiscoveryResolutionRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)
        DiscoveryResolutionRepository.shared.setModelContext(ctx)
        return ctx
    }

    @Test func saveAndFetchBySourceEventId() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let r = DiscoveryResolution(
            resolutionId: "res-1",
            sourceEventId: "evt-discovery-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            actorUserId: "u1",
            finalOutcome: .acceptedFirst,
            tripScoringOutcome: .acceptedFirst,
            personalHistoryOutcome: .acceptedFirst,
            finalXpAward: 10,
            xpReason: .competitiveFirstFinder,
            resolvedAgainstEventId: nil,
            serverSequence: 1,
            resolutionVersion: 1,
            resolvedAtServer: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try DiscoveryResolutionRepository.shared.save(r)
        let loaded = try DiscoveryResolutionRepository.shared.resolution(bySourceEventId: "evt-discovery-1")
        #expect(loaded?.resolutionId == "res-1")
        #expect(loaded?.finalXpAward == 10)
        #expect(loaded?.tripScoringOutcome == .acceptedFirst)
        #expect(loaded?.personalHistoryOutcome == .acceptedFirst)
    }

    @Test func upsertByResolutionId() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let r1 = DiscoveryResolution(
            resolutionId: "same-id",
            sourceEventId: "src-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .pending,
            tripScoringOutcome: .pending,
            personalHistoryOutcome: .pending,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution,
            serverSequence: 1,
            resolutionVersion: 1
        )
        try DiscoveryResolutionRepository.shared.save(r1)
        let r2 = DiscoveryResolution(
            resolutionId: "same-id",
            sourceEventId: "src-1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedShared,
            tripScoringOutcome: .acceptedShared,
            personalHistoryOutcome: .acceptedFirst,
            finalXpAward: 10,
            xpReason: .collaborativeSharedFinder,
            serverSequence: 2,
            resolutionVersion: 2
        )
        try DiscoveryResolutionRepository.shared.save(r2)
        let list = try DiscoveryResolutionRepository.shared.resolutions(sessionId: sessionId, gameInstanceId: gameId, itemId: "TX")
        #expect(list.count == 1)
        #expect(list[0].finalOutcome == .acceptedShared)
        #expect(list[0].finalXpAward == 10)
    }

    @Test func resolutionsForSessionGameItem() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        try DiscoveryResolutionRepository.shared.save(
            DiscoveryResolution(
                resolutionId: "r-a",
                sourceEventId: "e-a",
                sessionId: sessionId,
                gameInstanceId: gameId,
                itemId: "NY",
                actorUserId: "u1",
                finalOutcome: .acceptedFirst,
                tripScoringOutcome: .acceptedFirst,
                personalHistoryOutcome: .acceptedFirst,
                finalXpAward: 10,
                xpReason: .soloNewDiscovery,
                serverSequence: 1,
                resolutionVersion: 1
            )
        )
        try DiscoveryResolutionRepository.shared.save(
            DiscoveryResolution(
                resolutionId: "r-b",
                sourceEventId: "e-b",
                sessionId: sessionId,
                gameInstanceId: gameId,
                itemId: "NY",
                actorUserId: "u2",
                finalOutcome: .acceptedLate,
                tripScoringOutcome: .acceptedLate,
                personalHistoryOutcome: .acceptedLate,
                finalXpAward: 5,
                xpReason: .competitiveLateFinder,
                serverSequence: 2,
                resolutionVersion: 1
            )
        )
        let rows = try DiscoveryResolutionRepository.shared.resolutions(sessionId: sessionId, gameInstanceId: gameId, itemId: "NY")
        #expect(rows.count == 2)
    }
}
