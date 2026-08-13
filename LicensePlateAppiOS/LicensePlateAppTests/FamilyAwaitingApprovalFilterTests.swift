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
        let all = FamilyAwaitingApprovalFilter.awaitingApprovalInvites(
            from: invites,
            userId: userId,
            consumedInviteIds: []
        )
        XCTAssertEqual(all.map(\.inviteId), ["i-new", "i-old"])

        let primary = FamilyAwaitingApprovalFilter.primaryAwaitingApprovalInvite(
            from: invites,
            userId: userId,
            consumedInviteIds: []
        )
        XCTAssertEqual(primary?.inviteId, "i-new")
        XCTAssertEqual(primary?.familyName, "Newer Fam")
    }

    /// COPPA F-8 bug B: the server never flips an APPROVED family invite out of
    /// `accepted` (only the decline path does), so after the member is removed the old
    /// invite would resurface as a phantom "waiting for captain approval".
    func testConsumedInvitesAreNotAwaitingApproval() {
        let userId = "u-1"
        let exp = Date().addingTimeInterval(3600)
        let consumed = Invite(
            inviteId: "i-consumed",
            type: .family,
            fromUserId: "captain",
            toUserId: userId,
            familyId: "fam-1",
            status: .accepted,
            method: .code,
            expiresAt: exp,
            createdAt: Date().addingTimeInterval(-600),
            familyName: "Joined Fam"
        )
        let stillWaiting = Invite(
            inviteId: "i-waiting",
            type: .family,
            fromUserId: "captain2",
            toUserId: userId,
            familyId: "fam-2",
            status: .accepted,
            method: .code,
            expiresAt: exp,
            createdAt: Date().addingTimeInterval(-60),
            familyName: "Other Fam"
        )

        // Removed from fam-1: the consumed invite must not read as a live request…
        XCTAssertNil(
            FamilyAwaitingApprovalFilter.primaryAwaitingApprovalInvite(
                from: [consumed],
                userId: userId,
                consumedInviteIds: ["i-consumed"]
            )
        )
        // …while a genuine, never-redeemed invite to another family still shows.
        XCTAssertEqual(
            FamilyAwaitingApprovalFilter.primaryAwaitingApprovalInvite(
                from: [consumed, stillWaiting],
                userId: userId,
                consumedInviteIds: ["i-consumed"]
            )?.inviteId,
            "i-waiting"
        )
    }
}
