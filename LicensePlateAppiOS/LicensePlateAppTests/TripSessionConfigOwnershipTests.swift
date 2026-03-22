//
//  TripSessionConfigOwnershipTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.2 — TripSession is trip-only; no game config (enabled countries) on session.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct TripSessionConfigOwnershipTests {

    @Test func tripSessionHasOnlyTripLevelFields() async throws {
        let session = TripSession(
            id: UUID(),
            name: "Trip",
            status: .active,
            createdAt: Date(),
            createdBy: "user1",
            participants: [TripParticipant(userId: "user1", role: .owner, joinedAt: Date())]
        )
        #expect(session.id != UUID())
        #expect(session.name == "Trip")
        #expect(session.status == .active)
        #expect(session.mode == .solo)
        #expect(session.participants.count == 1)
        #expect(session.riskFlags == nil)
    }

    @Test func tripSessionMinimalInitSucceeds() async throws {
        let session = TripSession(name: "Minimal")
        #expect(session.name == "Minimal")
        #expect(session.status == .created)
        #expect(session.mode == .solo)
        #expect(session.participants.isEmpty)
    }
}
