//
//  GameplayAppendCallableResponseParserTests.swift
//  LicensePlateAppTests
//
//  Step 13 — Callable response decoding for gameplay sync.
//

import Foundation
import Testing
@testable import LicensePlateApp

@Suite("GameplayAppendCallableResponseParser")
@MainActor
struct GameplayAppendCallableResponseParserTests {

    @Test func legacySuccessAccepted() throws {
        let data: [String: Any] = ["success": true]
        let outcome = try GameplayAppendCallableResponseParser.outcome(from: data, uploadedEventId: "evt-1")
        guard case .accepted = outcome else {
            Issue.record("Expected accepted")
            return
        }
    }

    @Test func supersededParsesRejection() throws {
        let data: [String: Any] = [
            "success": true,
            "resolution": "superseded",
            "rejectionEvent": [
                "id": "srvrej_abc",
                "sessionId": "550e8400-e29b-41d4-a716-446655440000",
                "kind": "discovery_rejected",
                "timestamp": 1_700_000_000.0,
                "actorId": "user-b",
                "payload": [
                    "rejectionReason": DiscoveryRejectionReason.serverRejectedLateCompetitive.rawValue,
                    "regionId": "CA",
                    "gameInstanceId": "660e8400-e29b-41d4-a716-446655440001",
                    "participantId": "user-b",
                    "firstFinderParticipantId": "user-a",
                    "clientAttemptEventId": "abc",
                ] as [String: String],
            ] as [String: Any],
        ]
        let outcome = try GameplayAppendCallableResponseParser.outcome(from: data, uploadedEventId: "abc")
        guard case let .superseded(localId, rejection) = outcome else {
            Issue.record("Expected superseded")
            return
        }
        #expect(localId == "abc")
        #expect(rejection.id == "srvrej_abc")
        #expect(rejection.kind == .discoveryRejected)
    }

    @Test func deleteEventRemovesRow() throws {
        let repo = MockTripActivityEventRepository()
        let sid = UUID()
        let e = TripActivityEvent(id: "to-delete", sessionId: sid, kind: .regionFound, payload: [:])
        try repo.append(e)
        try repo.deleteEvent(id: "to-delete")
        let loaded = try repo.event(byId: "to-delete")
        #expect(loaded == nil)
    }
}
