//
//  TripActivityEventDiscoveryReplayTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripActivityEventDiscoveryReplayTests {

    @Test func supersededRejectionStripsLaterRegionFound() {
        let gid = UUID()
        let sid = UUID()
        let events: [TripActivityEvent] = [
            TripActivityEvent(
                id: "early",
                sessionId: sid,
                kind: .regionFound,
                timestamp: Date(timeIntervalSince1970: 100),
                payload: [
                    TripActivityEventPayloadKey.gameInstanceId: gid.uuidString,
                    TripActivityEventPayloadKey.regionId: "CA",
                    TripActivityEventPayloadKey.participantId: "u1",
                    TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
                    TripActivityEventPayloadKey.serverCommittedAt: "2000",
                ]
            ),
            TripActivityEvent(
                id: "late",
                sessionId: sid,
                kind: .regionFound,
                timestamp: Date(timeIntervalSince1970: 200),
                payload: [
                    TripActivityEventPayloadKey.gameInstanceId: gid.uuidString,
                    TripActivityEventPayloadKey.regionId: "CA",
                    TripActivityEventPayloadKey.participantId: "u2",
                    TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
                    TripActivityEventPayloadKey.serverCommittedAt: "1000",
                ]
            ),
            TripActivityEvent(
                id: "rej",
                sessionId: sid,
                kind: .discoveryRejected,
                timestamp: Date(timeIntervalSince1970: 300),
                actorId: "u2",
                payload: [
                    TripActivityEventPayloadKey.gameInstanceId: gid.uuidString,
                    TripActivityEventPayloadKey.regionId: "CA",
                    TripActivityEventPayloadKey.participantId: "u2",
                    TripActivityEventPayloadKey.rejectionReason: DiscoveryOutcome.serverRejectedSupersededByEarlierTimestamp.rawValue,
                    TripActivityEventPayloadKey.supersededRegionFoundEventId: "late",
                    TripActivityEventPayloadKey.firstFinderParticipantId: "u1",
                ]
            ),
        ]
        let (discoveries, _) = TripActivityEventDiscoveryReplay.replay(events: events, gameInstanceFilter: gid)
        #expect(discoveries.count == 1)
        #expect(discoveries[0].participantId == "u1")
    }

    @Test func orderingUsesServerCommittedAtWhenDiscoveredAtEqual() {
        let gid = UUID()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let a = GameDiscovery(
            id: "a",
            gameInstanceId: gid,
            participantId: "u1",
            targetId: "CA",
            discoveredAt: t,
            serverCommittedAt: Date(timeIntervalSince1970: 100),
            inputMethod: .list
        )
        let b = GameDiscovery(
            id: "b",
            gameInstanceId: gid,
            participantId: "u2",
            targetId: "CA",
            discoveredAt: t,
            serverCommittedAt: Date(timeIntervalSince1970: 200),
            inputMethod: .list
        )
        #expect(GameDiscovery.orderingAscending(a, b))
        #expect(!GameDiscovery.orderingAscending(b, a))
    }
}
