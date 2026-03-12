//
//  DiscoverySpamHeuristicsTests.swift
//  LicensePlateAppTests
//
//  Step 11 — DiscoverySpamHeuristics: advisory risk flags from found regions and recent events.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoverySpamHeuristicsTests {

    private func makeFoundRegion(regionID: String, foundAt: Date = Date()) -> FoundRegion {
        FoundRegion(
            regionID: regionID,
            foundAt: foundAt,
            inputMethod: .list,
            foundBy: nil,
            foundAtLocation: nil
        )
    }

    private func makeEvent(date: Date, regionID: String, isAdd: Bool) -> DiscoveryChangeEvent {
        DiscoveryChangeEvent(date: date, regionID: regionID, isAdd: isAdd)
    }

    @Test func emptyInputReturnsNoFlags() async throws {
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: [], recentEvents: [])
        #expect(flags.isEmpty)
    }

    @Test func impossibleBurstManyAddsInShortWindow() async throws {
        let now = Date()
        let events = (0..<11).map { i in
            makeEvent(date: now.addingTimeInterval(-Double(i)), regionID: "region-\(i)", isAdd: true)
        }
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: [], recentEvents: events)
        #expect(flags.contains(.impossibleBurst))
    }

    @Test func rapidFindUnfindLoopSameRegionAddRemoveAdd() async throws {
        let now = Date()
        let events: [DiscoveryChangeEvent] = [
            makeEvent(date: now.addingTimeInterval(-4), regionID: "us-ca", isAdd: true),
            makeEvent(date: now.addingTimeInterval(-2), regionID: "us-ca", isAdd: false),
            makeEvent(date: now, regionID: "us-ca", isAdd: true)
        ]
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: [], recentEvents: events)
        #expect(flags.contains(.rapidFindUnfindLoop))
    }

    @Test func suspiciousRepeatedTogglesSameRegion() async throws {
        let now = Date()
        let events: [DiscoveryChangeEvent] = (0..<4).map { i in
            makeEvent(date: now.addingTimeInterval(-Double(9 - i)), regionID: "us-ny", isAdd: i % 2 == 0)
        }
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: [], recentEvents: events)
        #expect(flags.contains(.suspiciousRepeatedToggles))
    }

    @Test func conflictingLocalTimestampFuture() async throws {
        let future = Date().addingTimeInterval(3600)
        let found = [makeFoundRegion(regionID: "us-ca", foundAt: future)]
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: found, recentEvents: [])
        #expect(flags.contains(.conflictingLocalTimestamp))
    }

    @Test func conflictingLocalTimestampTooOld() async throws {
        let oneYearAgo = Date().addingTimeInterval(-400 * 24 * 3600)
        let found = [makeFoundRegion(regionID: "us-ca", foundAt: oneYearAgo)]
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: found, recentEvents: [])
        #expect(flags.contains(.conflictingLocalTimestamp))
    }

    @Test func duplicateDiscoveryAnomalySameRegionID() async throws {
        let t = Date()
        let found = [
            makeFoundRegion(regionID: "us-ca", foundAt: t),
            makeFoundRegion(regionID: "us-ca", foundAt: t.addingTimeInterval(1))
        ]
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: found, recentEvents: [])
        #expect(flags.contains(.duplicateDiscoveryAnomaly))
    }

    @Test func normalActivityNoFlags() async throws {
        let now = Date()
        let found = [makeFoundRegion(regionID: "us-ca", foundAt: now.addingTimeInterval(-60))]
        let events = [
            makeEvent(date: now.addingTimeInterval(-30), regionID: "us-ca", isAdd: true)
        ]
        let flags = DiscoverySpamHeuristics.evaluate(foundRegions: found, recentEvents: events)
        #expect(flags.isEmpty)
    }
}
