//
//  InviteSnapshotTripGameSeparationTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.6 Phase D — Trip participation (TripMode) vs game count lines stay separate.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct InviteSnapshotTripGameSeparationTests {

    private func makeInvite(tripMode: String = TripMode.multiplayer.rawValue) -> TripInvite {
        TripInvite(
            inviteId: UUID().uuidString,
            tripSessionId: UUID().uuidString,
            tripName: "Test Trip",
            tripMode: tripMode,
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

    @Test func tripParticipationLineUsesTripModeDisplayNameNotRawStorage() {
        let invite = makeInvite(tripMode: TripMode.solo.rawValue)
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: nil)
        let expectedMode = TripMode.solo.localizedDisplayName
        #expect(snapshot.tripParticipationLine.contains(expectedMode))
        #expect(!snapshot.tripParticipationLine.contains(invite.tripMode))
    }

    @Test func gamesOnTripLineSeparateFromTripParticipationWhenCountProvided() {
        let invite = makeInvite(tripMode: TripMode.multiplayer.rawValue)
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: 3)
        #expect(snapshot.gamesOnTripLine != nil)
        #expect(snapshot.gamesOnTripLine == "%d games".localized(3))
        #expect(!snapshot.tripParticipationLine.contains("3"))
        #expect(!snapshot.tripParticipationLine.lowercased().contains("game"))
    }

    @Test func singleGameUsesSingularLocalizedString() {
        let invite = makeInvite()
        let snapshot = InviteDisplaySnapshot.make(from: invite, localGameCount: 1)
        #expect(snapshot.gamesOnTripLine == "1 game".localized)
    }
}
