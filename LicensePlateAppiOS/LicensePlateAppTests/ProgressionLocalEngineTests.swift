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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [e1],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [e1],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: ["rf1"],
            rewards: rewards
        )
        #expect(d == .zero)
    }

    @Test func gameEndedPendsTheFindAndTheGameEndedBonus() {
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [rf, ge],
            rosterUserIds: ["u1", "u2"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
            rewards: rewards
        )
        #expect(d.totalXp == rewards.xp.baseDiscoveryXp + rewards.xp.gameEndedBonusXp)
    }

    /// §3.1.1 item 25: placement, trip victory and participation are server-decided, so a game and
    /// trip end pend only the outcome-independent bonuses — for the clear local winner by contribution
    /// too. The engine takes no game mode at all; competitive-mode coverage lives in
    /// `LocalCompletionXpLedgerTests.competitiveGameAndTripEndMintNoServerDecidedRows`.
    @Test func aClearLocalWinnerPendsOnlyTheOutcomeIndependentBonuses() {
        func find(_ id: String, _ who: String, _ region: String, at seconds: TimeInterval) -> TripActivityEvent {
            TripActivityEvent(
                id: id,
                sessionId: sessionId,
                kind: .regionFound,
                timestamp: Date(timeIntervalSince1970: seconds),
                actorId: who,
                payload: [
                    TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                    TripActivityEventPayloadKey.regionId: region,
                    TripActivityEventPayloadKey.participantId: who,
                    TripActivityEventPayloadKey.inputMethod: "list",
                ]
            )
        }
        let ge = TripActivityEvent(
            id: "ge1",
            sessionId: sessionId,
            kind: .gameEnded,
            timestamp: Date(timeIntervalSince1970: 4),
            actorId: "u1",
            payload: [TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString]
        )
        let te = TripActivityEvent(
            id: "te1",
            sessionId: sessionId,
            kind: .tripEnded,
            timestamp: Date(timeIntervalSince1970: 5),
            actorId: "u1"
        )
        let events = [find("rf1", "u1", "US-CA", at: 1), find("rf2", "u1", "US-NV", at: 2), find("rf3", "u2", "US-OR", at: 3), ge, te]
        func pending(_ subject: String) -> ProgressionPendingDelta {
            ProgressionLocalEngine.pendingDeltaForSession(
                sortedSessionEvents: events,
                rosterUserIds: ["u1", "u2"],
                subjectUserId: subject,
                serverAppliedEventIds: [],
                rewards: rewards
            )
        }
        let completion = rewards.xp.gameEndedBonusXp + rewards.xp.tripEndedBonusXp
        let winner = pending("u1")
        let runnerUp = pending("u2")
        #expect(winner.totalXp == rewards.xp.baseDiscoveryXp * 2 + completion)
        #expect(runnerUp.totalXp == rewards.xp.baseDiscoveryXp + completion)

        let components = [ge, te].flatMap {
            ProgressionLocalEngine.completionComponents(for: $0, rosterUserIds: ["u1", "u2"], rewards: rewards)
        }
        #expect(Set(components.map(\.reason.rawValue)) == [XpReasonCode.gameEnded.rawValue, XpReasonCode.tripEnded.rawValue])
        #expect(components.count == 4)
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [found1, removed, found2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [g1, g2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: [],
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [found1, found2],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: ["rf1"],
            rewards: rewards
        )
        #expect(d.acceptedRegionFindCount == 0)
        #expect(d.totalXp == 0)
    }

    /// §3.1.1 item 24. The server's invalid-participant rejection pays the find, so it counts as
    /// pending base until the server stamps it — otherwise the find drops out of the local totals
    /// between the supersede and the stamp. The device's own tap-time rejection carries the same
    /// reason but no `serverResolvedAt`; it earned nothing and must never count.
    @Test func serverInvalidParticipantRejectionCountsPendingButTheDevicesOwnDoesNot() {
        let reason = DiscoveryRejectionReason.rejectedInvalidParticipant.rawValue
        let serverRejection = TripActivityEvent(
            id: "srvrej_rf-solo",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 3),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-CA",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.rejectionReason: reason,
                TripActivityEventPayloadKey.clientAttemptEventId: "rf-solo",
                TripActivityEventPayloadKey.serverResolvedAt: "1786755660",
            ]
        )
        let tapTimeRejection = TripActivityEvent(
            id: "local-rejection",
            sessionId: sessionId,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: 4),
            actorId: "u1",
            payload: [
                TripActivityEventPayloadKey.gameInstanceId: gameId.uuidString,
                TripActivityEventPayloadKey.regionId: "US-NY",
                TripActivityEventPayloadKey.participantId: "u1",
                TripActivityEventPayloadKey.rejectionReason: reason,
            ]
        )
        func pending(applied: Set<String>) -> ProgressionPendingDelta {
            ProgressionLocalEngine.pendingDeltaForSession(
                sortedSessionEvents: [serverRejection, tapTimeRejection],
                rosterUserIds: ["u1"],
                subjectUserId: "u1",
                serverAppliedEventIds: applied,
                rewards: rewards
            )
        }

        #expect(ProgressionLocalEngine.serverRejectionPaysFind(serverRejection))
        #expect(!ProgressionLocalEngine.serverRejectionPaysFind(tapTimeRejection))
        let beforeStamp = pending(applied: [])
        #expect(beforeStamp.totalXp == rewards.xp.baseDiscoveryXp)
        #expect(beforeStamp.acceptedRegionFindCount == 1)
        let afterStamp = pending(applied: ["srvrej_rf-solo"])
        #expect(afterStamp.totalXp == 0)
        #expect(afterStamp.acceptedRegionFindCount == 0)
    }

    /// §3.1.1 item 24. A find the server paid off its `srvrej_` rejection does not count as pending,
    /// even while the local `region_found` is still queued (the callable's response never arrived):
    /// otherwise it counts on top of the server total and drops when the retry deletes it.
    @Test func regionFoundPaidOffItsServerRejectionIsNotPending() {
        let find = TripActivityEvent(
            id: "rf-queued",
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
        let d = ProgressionLocalEngine.pendingDeltaForSession(
            sortedSessionEvents: [find],
            rosterUserIds: ["u1"],
            subjectUserId: "u1",
            serverAppliedEventIds: [XpServerScopeKey.serverRejectionEventId(forClientEventId: "rf-queued")],
            rewards: rewards
        )
        #expect(d == .zero)
    }
}
