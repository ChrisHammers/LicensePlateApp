//
//  DiscoverySpamHeuristicsTests.swift
//  LicensePlateAppTests
//
//  Step 11 — DiscoverySpamHeuristics: context-based heuristics return typed [RiskFlag].
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoverySpamHeuristicsTests {

    private func makeContext(
        tripId: UUID = UUID(),
        subjectId: String = "us-ca",
        occurredAt: Date = Date(),
        previousDiscoveryTimestamps: [Date] = [],
        recentToggleCount: Int = 0,
        wasDuplicateCandidate: Bool = false,
        foundRegionTimestamps: [Date] = [],
        evaluationDate: Date = Date(),
        recentEvents: [DiscoveryChangeEvent] = []
    ) -> DiscoveryActionContext {
        DiscoveryActionContext(
            participantId: "user1",
            tripId: tripId,
            subjectId: subjectId,
            inputMethod: .tap,
            occurredAt: occurredAt,
            previousDiscoveryTimestamps: previousDiscoveryTimestamps,
            recentToggleCount: recentToggleCount,
            wasDuplicateCandidate: wasDuplicateCandidate,
            foundRegionTimestamps: foundRegionTimestamps,
            evaluationDate: evaluationDate,
            recentEvents: recentEvents
        )
    }

    private func makeEvent(date: Date, regionID: String, isAdd: Bool) -> DiscoveryChangeEvent {
        DiscoveryChangeEvent(date: date, regionID: regionID, isAdd: isAdd)
    }

    @Test func emptyContextReturnsNoFlags() async throws {
        let context = makeContext()
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.isEmpty)
    }

    @Test func burstManyAddsInShortWindow() async throws {
        let now = Date()
        let events = (0..<11).map { i in
            makeEvent(date: now.addingTimeInterval(-Double(i)), regionID: "region-\(i)", isAdd: true)
        }
        let context = makeContext(occurredAt: now, evaluationDate: now, recentEvents: events)
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .burstInputPattern }))
    }

    @Test func rapidUndoRedoSameRegionAddRemoveAdd() async throws {
        let now = Date()
        let events: [DiscoveryChangeEvent] = [
            makeEvent(date: now.addingTimeInterval(-4), regionID: "us-ca", isAdd: true),
            makeEvent(date: now.addingTimeInterval(-2), regionID: "us-ca", isAdd: false),
            makeEvent(date: now, regionID: "us-ca", isAdd: true)
        ]
        let context = makeContext(occurredAt: now, evaluationDate: now, recentEvents: events)
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .rapidUndoRedo }))
    }

    @Test func suspiciousToggleLoopSameRegion() async throws {
        let context = makeContext(recentToggleCount: 4)
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .suspiciousToggleLoop }))
    }

    @Test func impossibleTimestampFuture() async throws {
        let future = Date().addingTimeInterval(3600)
        let context = makeContext(foundRegionTimestamps: [future], evaluationDate: Date())
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .impossibleTimestamp }))
    }

    @Test func impossibleTimestampTooOld() async throws {
        let oneYearAgo = Date().addingTimeInterval(-400 * 24 * 3600)
        let context = makeContext(foundRegionTimestamps: [oneYearAgo], evaluationDate: Date())
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .impossibleTimestamp }))
    }

    @Test func duplicateDiscoveryWhenWasDuplicateCandidate() async throws {
        let context = makeContext(wasDuplicateCandidate: true)
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.contains(where: { $0.type == .duplicateDiscovery }))
    }

    @Test func normalActivityNoFlags() async throws {
        let now = Date()
        let context = makeContext(
            occurredAt: now,
            foundRegionTimestamps: [now.addingTimeInterval(-60)],
            evaluationDate: now,
            recentEvents: [makeEvent(date: now.addingTimeInterval(-30), regionID: "us-ca", isAdd: true)]
        )
        let flags = DiscoverySpamHeuristics().evaluate(context: context)
        #expect(flags.isEmpty)
    }
}
