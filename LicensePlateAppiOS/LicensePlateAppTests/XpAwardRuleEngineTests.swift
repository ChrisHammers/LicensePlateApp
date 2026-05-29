//
//  XpAwardRuleEngineTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpAwardRuleEngineTests {

    @Test func competitiveFirstFinderNet10() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedFirst,
            tripScoringOutcome: .acceptedFirst,
            personalHistoryOutcome: .acceptedFirst,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer)
        #expect(c.xpNet == 10)
        #expect(c.xpReason == .competitiveFirstFinder)
    }

    @Test func competitiveLateNet4() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedLate,
            tripScoringOutcome: .acceptedLate,
            personalHistoryOutcome: .acceptedLate,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer)
        #expect(c.xpNet == 4)
        #expect(c.xpReason == .competitiveLateFinder)
    }

    @Test func duplicateNet0() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .rejectedDuplicate,
            tripScoringOutcome: .rejectedDuplicate,
            personalHistoryOutcome: .rejectedDuplicate,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer)
        #expect(c.xpNet == 0)
        #expect(c.xpReason == .duplicateNoXp)
    }

    @Test func soloAcceptedFirstUsesSoloReason() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedFirst,
            tripScoringOutcome: .acceptedFirst,
            personalHistoryOutcome: .acceptedFirst,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .solo)
        #expect(c.xpNet == 10)
        #expect(c.xpReason == .soloNewDiscovery)
    }

    @Test func collaborativeSharedNet10() {
        let r = DiscoveryResolution(
            sourceEventId: "e1",
            sessionId: UUID(),
            gameInstanceId: UUID(),
            itemId: "TX",
            actorUserId: "u1",
            finalOutcome: .acceptedShared,
            tripScoringOutcome: .acceptedShared,
            personalHistoryOutcome: .acceptedShared,
            finalXpAward: 0,
            xpReason: .discoveryClaimPendingResolution
        )
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .collaborative, tripMode: .multiplayer)
        #expect(c.xpNet == 10)
        #expect(c.xpReason == .collaborativeSharedFinder)
    }
}
