//
//  XpAwardRuleEngineTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpAwardRuleEngineTests {

    private let rewards = ProgressionRewardsConfig.fixtureDefault

    @Test func competitiveFirstFinderSettlesBaseOnlyLocally() {
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
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer, rewards: rewards)
        #expect(c.xpNet == rewards.xp.baseDiscoveryXp)
        #expect(c.xpReason == .competitiveFirstFinder)
    }

    @Test func competitiveLateNet10() {
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
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer, rewards: rewards)
        #expect(c.xpNet == rewards.xp.baseDiscoveryXp)
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
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .multiplayer, rewards: rewards)
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
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .competitive, tripMode: .solo, rewards: rewards)
        #expect(c.xpNet == rewards.xp.baseDiscoveryXp)
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
        let c = XpAwardRuleEngine.compute(from: r, gameMode: .collaborative, tripMode: .multiplayer, rewards: rewards)
        #expect(c.xpNet == rewards.xp.baseDiscoveryXp)
        #expect(c.xpReason == .collaborativeSharedFinder)
    }
}
