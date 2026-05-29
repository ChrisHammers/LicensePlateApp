//
//  XpLedgerRepositoryTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct XpLedgerRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let ctx = ModelContext(container)
        XpLedgerRepository.shared.setModelContext(ctx)
        return ctx
    }

    private func sampleKey(sessionId: UUID, gameId: UUID) -> String {
        XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        ).storageString
    }

    @Test func appendAndFetchBySourceEventId() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let key = sampleKey(sessionId: sessionId, gameId: gameId)
        let e1 = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "src-99",
            sourceEventType: "region_found",
            itemId: "CA",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: key
        )
        try XpLedgerRepository.shared.append(e1)
        let bySource = try XpLedgerRepository.shared.ledgerEvents(sourceEventId: "src-99")
        #expect(bySource.count == 1)
        #expect(bySource[0].xpDelta == 10)
    }

    @Test func appendBaseDiscoveryIfAbsentIdempotent() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let key = sampleKey(sessionId: sessionId, gameId: gameId)
        let base = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "a1",
            sourceEventType: "region_found",
            itemId: "CA",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: key
        )
        let inserted1 = try XpLedgerRepository.shared.appendBaseDiscoveryIfAbsent(base)
        let inserted2 = try XpLedgerRepository.shared.appendBaseDiscoveryIfAbsent(
            XpLedgerEvent(
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "a2",
                sourceEventType: "region_found",
                itemId: "CA",
                grantKind: .finalDiscoveryAward,
                status: .final,
                xpDelta: 10,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: key
            )
        )
        #expect(inserted1 == true)
        #expect(inserted2 == false)
        let rows = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
        #expect(rows.count == 1)
    }

    @Test func appendBaseDiscoveryRejectsNonBaseGrantKinds() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let key = sampleKey(sessionId: sessionId, gameId: gameId)
        let bad = XpLedgerEvent(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "b1",
            sourceEventType: "region_found",
            itemId: "CA",
            grantKind: .reconciliationAdjustment,
            status: .final,
            xpDelta: -5,
            reasonCode: .duplicateNoXp,
            xpUniquenessKey: key
        )
        #expect(throws: XpLedgerRepositoryError.self) {
            try XpLedgerRepository.shared.appendBaseDiscoveryIfAbsent(bad)
        }
    }

    @Test func multipleAdjustmentsNetCorrectly() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let keyAdj = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "OR",
            xpCategory: .reconciliation
        ).storageString
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "s1",
                sourceEventType: "region_found",
                itemId: "OR",
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: 10,
                reasonCode: .competitiveFirstFinder,
                xpUniquenessKey: keyAdj
            )
        )
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "s2",
                sourceEventType: "region_found",
                itemId: "OR",
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: -3,
                reasonCode: .duplicateNoXp,
                xpUniquenessKey: keyAdj
            )
        )
        let net = try XpLedgerRepository.shared.netXpDelta(
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: "OR",
            includingStatuses: [.final, .provisional]
        )
        #expect(net == 7)
    }

    @Test func fetchByUniquenessKey() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let key = sampleKey(sessionId: sessionId, gameId: gameId)
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u1",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "x1",
                sourceEventType: "region_found",
                itemId: "CA",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 5,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key
            )
        )
        let rows = try XpLedgerRepository.shared.ledgerEvents(forUniquenessKey: key)
        #expect(rows.count == 1)
        #expect(rows[0].sourceEventId == "x1")
    }

    @Test func voidedExcludedFromNetWhenOnlyFinalProvisionalRequested() throws {
        _ = try makeContext()
        let sessionId = UUID()
        let gameId = UUID()
        let item = "WA"
        let key1 = XpLedgerKeyBuilder.uniquenessKey(userId: "u2", sessionId: sessionId, gameInstanceId: gameId, itemId: item, xpCategory: .baseRegionDiscovery).storageString
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u2",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "v1",
                sourceEventType: "region_found",
                itemId: item,
                grantKind: .reconciliationAdjustment,
                status: .voided,
                xpDelta: 0,
                reasonCode: .duplicateNoXp,
                xpUniquenessKey: key1
            )
        )
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u2",
                sessionId: sessionId,
                gameInstanceId: gameId,
                sourceEventId: "v2",
                sourceEventType: "region_found",
                itemId: item,
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: 10,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: key1
            )
        )
        let netFinalOnly = try XpLedgerRepository.shared.netXpDelta(
            userId: "u2",
            sessionId: sessionId,
            gameInstanceId: gameId,
            itemId: item,
            includingStatuses: [.final]
        )
        #expect(netFinalOnly == 10)
    }

    @Test func ledgerEventsByUserIdReturnsAllRowsForUser() throws {
        _ = try makeContext()
        let s1 = UUID()
        let s2 = UUID()
        let g1 = UUID()
        let g2 = UUID()
        let k1 = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u9",
            sessionId: s1,
            gameInstanceId: g1,
            itemId: "CA",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let k2 = XpLedgerKeyBuilder.uniquenessKey(
            userId: "u9",
            sessionId: s2,
            gameInstanceId: g2,
            itemId: "WA",
            xpCategory: .baseRegionDiscovery
        ).storageString
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u9",
                sessionId: s1,
                gameInstanceId: g1,
                sourceEventId: "e1",
                sourceEventType: "region_found",
                itemId: "CA",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: k1
            )
        )
        try XpLedgerRepository.shared.append(
            XpLedgerEvent(
                userId: "u9",
                sessionId: s2,
                gameInstanceId: g2,
                sourceEventId: "e2",
                sourceEventType: "region_found",
                itemId: "WA",
                grantKind: .finalDiscoveryAward,
                status: .final,
                xpDelta: 10,
                reasonCode: .soloNewDiscovery,
                xpUniquenessKey: k2
            )
        )
        let all = try XpLedgerRepository.shared.ledgerEvents(userId: "u9")
        #expect(all.count == 2)
        let scoped = try XpLedgerRepository.shared.ledgerEvents(userId: "u9", sessionId: s1)
        #expect(scoped.count == 1)
        #expect(scoped[0].itemId == "CA")
    }
}
