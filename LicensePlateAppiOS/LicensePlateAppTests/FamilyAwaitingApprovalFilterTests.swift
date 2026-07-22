//
//  FamilyAwaitingApprovalFilterTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class FamilyAwaitingApprovalFilterTests: XCTestCase {

    func testPrimaryAwaitingApprovalInvite() {
        let exp = Date().addingTimeInterval(900)
        let userId = "requester"
        let older = Date().addingTimeInterval(-120)
        let newer = Date()

        let pending = Invite(
            inviteId: "i-pending",
            type: .family,
            fromUserId: "captain",
            toUserId: userId,
            familyId: "fam-1",
            status: .pending,
            method: .code,
            expiresAt: exp,
            createdAt: newer,
            familyName: "Pending Fam"
        )
        let acceptedOlder = Invite(
            inviteId: "i-old",
            type: .family,
            fromUserId: "captain",
            toUserId: userId,
            familyId: "fam-1",
            status: .accepted,
            method: .code,
            expiresAt: exp,
            createdAt: older,
            familyName: "Older Fam"
        )
        let acceptedNewer = Invite(
            inviteId: "i-new",
            type: .family,
            fromUserId: "captain",
            toUserId: userId,
            familyId: "fam-2",
            status: .accepted,
            method: .qr,
            expiresAt: exp,
            createdAt: newer,
            familyName: "Newer Fam"
        )
        let otherUser = Invite(
            inviteId: "i-other",
            type: .family,
            fromUserId: "captain",
            toUserId: "someone-else",
            familyId: "fam-3",
            status: .accepted,
            method: .code,
            expiresAt: exp,
            createdAt: newer,
            familyName: "Other"
        )
        let friend = Invite(
            inviteId: "i-friend",
            type: .friend,
            fromUserId: "captain",
            toUserId: userId,
            status: .accepted,
            method: .search,
            expiresAt: exp,
            createdAt: newer
        )
        let declined = Invite(
            inviteId: "i-declined",
            type: .family,
            fromUserId: "captain",
            toUserId: userId,
            familyId: "fam-4",
            status: .declined,
            method: .code,
            expiresAt: exp,
            createdAt: newer,
            familyName: "Declined Fam"
        )

        let invites = [pending, acceptedOlder, acceptedNewer, otherUser, friend, declined]
        let all = FamilyAwaitingApprovalFilter.awaitingApprovalInvites(from: invites, userId: userId)
        XCTAssertEqual(all.map(\.inviteId), ["i-new", "i-old"])

        let primary = FamilyAwaitingApprovalFilter.primaryAwaitingApprovalInvite(
            from: invites,
            userId: userId
        )
        XCTAssertEqual(primary?.inviteId, "i-new")
        XCTAssertEqual(primary?.familyName, "Newer Fam")
    }
}
