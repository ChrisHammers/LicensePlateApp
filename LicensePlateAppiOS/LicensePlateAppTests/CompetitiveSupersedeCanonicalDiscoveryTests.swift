//
//  CompetitiveSupersedeCanonicalDiscoveryTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct CompetitiveSupersedeCanonicalDiscoveryTests {

    @Test func regionFoundEventReturnsNilWhenFirstFinderMetadataMissing() {
        let sid = UUID()
        let rejection = TripActivityEvent(
            id: "srvrej_x",
            sessionId: sid,
            kind: .discoveryRejected,
            timestamp: .now,
            actorId: "late-user",
            payload: [
                TripActivityEventPayloadKey.regionId: "CA",
                TripActivityEventPayloadKey.gameInstanceId: UUID().uuidString,
                TripActivityEventPayloadKey.rejectionReason: DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue,
            ]
        )
        #expect(CompetitiveSupersedeCanonicalDiscovery.regionFoundEvent(from: rejection) == nil)
    }

    @Test func regionFoundEventBuildsCanonicalDiscoveryFromRejectionPayload() {
        let sid = UUID()
        let gid = UUID()
        let ts: TimeInterval = 1_700_000_000
        let rejection = TripActivityEvent(
            id: "srvrej_client1",
            sessionId: sid,
            kind: .discoveryRejected,
            timestamp: Date(timeIntervalSince1970: ts + 100),
            actorId: "late-user",
            payload: [
                TripActivityEventPayloadKey.regionId: "TX",
                TripActivityEventPayloadKey.gameInstanceId: gid.uuidString,
                TripActivityEventPayloadKey.rejectionReason: DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue,
                TripActivityEventPayloadKey.firstFinderEventId: "winner-found-1",
                TripActivityEventPayloadKey.firstFinderParticipantId: "alice",
                TripActivityEventPayloadKey.firstFinderDiscoveredAt: String(Int(ts)),
                TripActivityEventPayloadKey.inputMethod: FoundRegion.InputMethod.list.rawValue,
            ]
        )
        let found = CompetitiveSupersedeCanonicalDiscovery.regionFoundEvent(from: rejection)
        #expect(found != nil)
        #expect(found?.id == "winner-found-1")
        #expect(found?.kind == .regionFound)
        #expect(found?.sessionId == sid)
        #expect(found?.actorId == "alice")
        #expect(abs(found!.timestamp.timeIntervalSince1970 - ts) < 0.01)
        #expect(found?.payload?[TripActivityEventPayloadKey.regionId] == "TX")
        #expect(found?.payload?[TripActivityEventPayloadKey.gameInstanceId] == gid.uuidString)
        #expect(found?.payload?[TripActivityEventPayloadKey.participantId] == "alice")
        #expect(found?.payload?[TripActivityEventPayloadKey.inputMethod] == FoundRegion.InputMethod.list.rawValue)
    }
}
