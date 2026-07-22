//
//  FamilyOutgoingInviteFilterTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class FamilyOutgoingInviteFilterTests: XCTestCase {

    func testPendingOutgoingFiltersByFamilyAndStatus() {
        let exp = Date().addingTimeInterval(900)
        let familyId = "fam-1"

        let pending = Invite(
            inviteId: "i1",
            type: .family,
            fromUserId: "captain",
            toUserId: "invitee",
            familyId: familyId,
            status: .pending,
            method: .search,
            expiresAt: exp,
            createdAt: Date()
        )
        let otherFamily = Invite(
            inviteId: "i2",
            type: .family,
            fromUserId: "captain",
            toUserId: "other",
            familyId: "fam-2",
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let accepted = Invite(
            inviteId: "i3",
            type: .family,
            fromUserId: "captain",
            toUserId: "done",
            familyId: familyId,
            status: .accepted,
            method: .search,
            expiresAt: exp
        )
        let friend = Invite(
            inviteId: "i4",
            type: .friend,
            fromUserId: "captain",
            toUserId: "buddy",
            status: .pending,
            method: .search,
            expiresAt: exp
        )

        let result = FamilyOutgoingInviteFilter.pendingOutgoing(
            from: [pending, otherFamily, accepted, friend],
            familyId: familyId
        )

        XCTAssertEqual(result.map(\.inviteId), ["i1"])
        XCTAssertEqual(
            FamilyOutgoingInviteFilter.pendingInviteeIds(
                from: [pending, otherFamily, accepted, friend],
                familyId: familyId
            ),
            ["invitee"]
        )
    }
}
