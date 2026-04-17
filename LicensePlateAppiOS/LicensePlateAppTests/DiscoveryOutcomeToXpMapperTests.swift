//
//  DiscoveryOutcomeToXpMapperTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DiscoveryOutcomeToXpMapperTests {

    @Test func mapsLateToFinalPhase() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedLate,
            tripScoringOutcome: .acceptedLate,
            personalHistoryOutcome: .acceptedLate,
            finalXpAward: 4,
            xpReason: .competitiveLateFinder
        )
        let m = DiscoveryOutcomeToXpMapper.map(resolution: r, gameMode: .competitive, tripMode: .multiplayer)
        #expect(m.finalNetXp == 4)
        #expect(m.resolvedXpPhase == .final)
    }

    @Test func pendingMapsToProvisionalPhase() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .pending,
            tripScoringOutcome: .pending,
            personalHistoryOutcome: .pending,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let m = DiscoveryOutcomeToXpMapper.map(resolution: r, gameMode: .competitive, tripMode: .multiplayer)
        #expect(m.finalNetXp == 0)
        #expect(m.resolvedXpPhase == .provisional)
    }
}
