//
//  ProgressionLocalEngineTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionLocalEngineTests {

    private let sessionId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let gameId = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001")!
    private let rewards = ProgressionRewardsConfig.fixtureDefault

    @Test func pendingRegionFoundWhenNotOnServer() {
        let e1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.inputMethod: "list",
            ]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .competitive, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [e1],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        #expect(d.totalXp == rewards.xp.baseDiscoveryXp)
        #expect(d.acceptedRegionFindCount == 1)
    }

    @Test func noPendingWhenServerAlreadyAppliedRegionFound() {
        let e1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.inputMethod: "list",
            ]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .competitive, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [e1],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: ["rf1"],
            gamesById: games,
            rewards: rewards
        )
        #expect(d == .zero)
    }

    @Test func collaborativeGameEndedDoesNotAwardCompetitiveFirstPlace() {
        let rf = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.inputMethod: "list",
            ]
        )
        let ge = TripActivityEvent(
            id: "ge1",
            sessionId: sessionId,
            kind: .gameEnded,
            timestamp: Date(timeIntervalSince1970: 2),
            actorId: "u1",
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .collaborative, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [rf, ge],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        #expect(d.competitiveFirstPlaceFinishes == 0)
        #expect(d.everCompetitiveFirstPlace == false)
        #expect(d.totalXp == rewards.xp.baseDiscoveryXp + rewards.xp.gameEndedBonusXp)
    }

    @Test func competitiveTieAwardsBothFirstPlacePending() {
        let rf1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.inputMethod: "list",
            ]
        )
        let rf2 = TripActivityEvent(
            id: "rf2",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 2),
            actorId: "u2",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-NV",
                TripActivityEventPayloadKey.participantId: "u2",
                TripActivityEventPayloadKey.inputMethod: "list",
            ]
        )
        let ge = TripActivityEvent(
            id: "ge1",
            sessionId: sessionId,
            kind: .gameEnded,
            timestamp: Date(timeIntervalSince1970: 3),
            actorId: "u1",
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .competitive, teams: []),
        ]
        let d1 = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [rf1, rf2, ge],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        let d2 = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [rf1, rf2, ge],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u2",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        #expect(d1.competitiveFirstPlaceFinishes == 1)
        #expect(d2.competitiveFirstPlaceFinishes == 1)
        #expect(d1.totalXp == rewards.xp.baseDiscoveryXp + rewards.xp.gameEndedBonusXp + rewards.xp.competitiveFirstPlaceFinishBonusXp)
        #expect(d2.totalXp == rewards.xp.baseDiscoveryXp + rewards.xp.gameEndedBonusXp + rewards.xp.competitiveFirstPlaceFinishBonusXp)
    }

    @Test func sameScopedRefindDoesNotAddPendingAgain() {
        let found1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let removed = TripActivityEvent(
            id: "rr1",
            sessionId: sessionId,
            kind: .regionRemoved,
            timestamp: Date(timeIntervalSince1970: 2),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.removedDiscoveryEventId: "rf1",
            ]
        )
        let found2 = TripActivityEvent(
            id: "rf2",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 3),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .competitive, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [found1, removed, found2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        #expect(d.acceptedRegionFindCount == 1)
        #expect(d.totalXp == GameProgressionXPRewards.baseDiscoveryXp)
    }

    @Test func differentGamesSameRegionBothCountPending() {
        let game2 = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440002")!
        let g1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let g2 = TripActivityEvent(
            id: "rf2",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 2),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: game2.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .collaborative, teams: []),
            game2: ProgressionGameSnapshot(id: game2, gameMode: .collaborative, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [g1, g2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            gamesById: games,
            rewards: rewards
        )
        #expect(d.acceptedRegionFindCount == 2)
        #expect(d.totalXp == rewards.xp.baseDiscoveryXp * 2)
    }

    @Test func appliedAnchorSuppressesPendingAndRefindDoesNotReplaceAnchor() {
        let found1 = TripActivityEvent(
            id: "rf1",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 1),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let found2 = TripActivityEvent(
            id: "rf2",
            sessionId: sessionId,
            kind: .regionFound,
            timestamp: Date(timeIntervalSince1970: 2),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
            ]
        )
        let games: [UUID: ProgressionGameSnapshot] = [
            gameId: ProgressionGameSnapshot(id: gameId, gameMode: .collaborative, teams: []),
        ]
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [found1, found2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: ["rf1"],
            gamesById: games,
            rewards: rewards
        )
        #expect(d.acceptedRegionFindCount == 0)
        #expect(d.totalXp == 0)
    }
}
