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

    /// §3.1.1 item 24. A collaborative game reaches `.acceptedLate` only through the server's
    /// invalid-participant rejection; nobody won a race, so the find keeps the label its provisional
    /// row carried rather than reading "competitive late finder".
    @Test func collaborativeAcceptedLateKeepsTheSharedLabel() {
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
        let multiplayer = XpAwardRuleEngine.compute(from: r, gameMode: .collaborative, tripMode: .multiplayer, rewards: rewards)
        #expect(multiplayer.xpNet == rewards.xp.baseDiscoveryXp)
        #expect(multiplayer.xpReason == .collaborativeSharedFinder)
        let solo = XpAwardRuleEngine.compute(from: r, gameMode: .collaborative, tripMode: .solo, rewards: rewards)
        #expect(solo.xpNet == rewards.xp.baseDiscoveryXp)
        #expect(solo.xpReason == .soloNewDiscovery)
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
