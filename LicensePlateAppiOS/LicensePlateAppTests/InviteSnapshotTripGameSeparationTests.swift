//
//  InviteSnapshotTripGameSeparationTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.6 Phase D — Invite row: game count line vs other metadata.
//  Step 6.10 — No trip participation line on invites; participation is roster-derived elsewhere.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct InviteSnapshotTripGameSeparationTests {

    private func makeInvite() -> TripInvite {
        TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Test Trip",
            fromUserId: "inviter",
            toUserId: "invitee",
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )
    }

    @Test func gamesOnTripLineNilWhenLocalCountUnknown() {
        let invite = makeInvite()
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: nil)
        #expect(snapshot.gamesOnTripLine == nil)
    }

    @Test func gamesOnTripLineSeparateFromTripNameWhenCountProvided() {
        let invite = makeInvite()
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: 3)
        #expect(snapshot.gamesOnTripLine != nil)
        #expect(snapshot.gamesOnTripLine == "%d games".localized(3))
        #expect(snapshot.tripName == "Test Trip")
        #expect(!snapshot.counterpartyLine.contains("3"))
    }

    @Test func singleGameUsesSingularLocalizedString() {
        let invite = makeInvite()
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: 1)
        #expect(snapshot.gamesOnTripLine == "1 game".localized)
    }
}
