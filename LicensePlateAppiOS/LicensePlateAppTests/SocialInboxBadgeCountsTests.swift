//
//  SocialInboxBadgeCountsTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class SocialInboxBadgeCountsTests: XCTestCase {

    private let exp = Date().addingTimeInterval(86400)
    private let me = "user-me"
    private let other = "user-other"
    private let familyId = "family-1"

    func testCountsIncomingFriendAndFamilyOnly() {
        let incomingFriend = Invite(
            inviteId: "f1",
            type: .friend,
            fromUserId: other,
            toUserId: me,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let outgoingFriend = Invite(
            inviteId: "f2",
            type: .friend,
            fromUserId: me,
            toUserId: other,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let incomingFamily = Invite(
            inviteId: "fam1",
            type: .family,
            fromUserId: other,
            toUserId: me,
            familyId: familyId,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let acceptedFamily = Invite(
            inviteId: "fam2",
            type: .family,
            fromUserId: other,
            toUserId: me,
            familyId: "family-2",
            status: .accepted,
            method: .search,
            expiresAt: exp
        )

        let counts = SocialInboxBadgeCounts.counts(
            from: [incomingFriend, outgoingFriend, incomingFamily, acceptedFamily],
            userId: me
        )

        XCTAssertEqual(counts.friend, 1)
        XCTAssertEqual(counts.family, 1)
        XCTAssertEqual(counts.familyApprovals, 0)
        XCTAssertEqual(counts.familyInbox, 1)
        XCTAssertEqual(counts.total, 2)
    }

    func testEmptyWhenNoPendingIncoming() {
        let counts = SocialInboxBadgeCounts.counts(from: [], userId: me)
        XCTAssertEqual(counts, SocialInboxBadgeCounts.Counts(friend: 0, family: 0, familyApprovals: 0))
    }

    func testCountsPendingApprovalsForCreator() {
        let creator = FamilyMember(familyId: familyId, userId: me, role: .creator)
        let pending = PendingJoinRequest(
            requestId: "req-1",
            familyId: familyId,
            userId: other,
            requestedBy: other,
            method: .code,
            status: .pending
        )
        let approved = PendingJoinRequest(
            requestId: "req-2",
            familyId: familyId,
            userId: "user-3",
            requestedBy: "user-3",
            method: .search,
            status: .approved
        )

        let counts = SocialInboxBadgeCounts.counts(
            from: [],
            userId: me,
            pendingRequestsByFamily: [familyId: [pending, approved]],
            membersByFamily: [familyId: [creator]],
            activeFamilyId: familyId
        )

        XCTAssertEqual(counts.familyApprovals, 1)
        XCTAssertEqual(counts.familyInbox, 1)
        XCTAssertEqual(counts.total, 1)
    }

    func testIgnoresApprovalsWhenViewerIsNotManager() {
        let scout = FamilyMember(familyId: familyId, userId: me, role: .scout)
        let pending = PendingJoinRequest(
            requestId: "req-1",
            familyId: familyId,
            userId: other,
            requestedBy: other,
            method: .code,
            status: .pending
        )

        let counts = SocialInboxBadgeCounts.counts(
            from: [],
            userId: me,
            pendingRequestsByFamily: [familyId: [pending]],
            membersByFamily: [familyId: [scout]],
            activeFamilyId: familyId
        )

        XCTAssertEqual(counts.familyApprovals, 0)
        XCTAssertEqual(counts.total, 0)
    }

    func testTotalIncludesFriendFamilyInviteAndApproval() {
        let incomingFriend = Invite(
            inviteId: "f1",
            type: .friend,
            fromUserId: other,
            toUserId: me,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let incomingFamily = Invite(
            inviteId: "fam1",
            type: .family,
            fromUserId: other,
            toUserId: me,
            familyId: "family-other",
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let captain = FamilyMember(familyId: familyId, userId: me, role: .captain)
        let pendingApproval = PendingJoinRequest(
            requestId: "req-1",
            familyId: familyId,
            userId: "joiner",
            requestedBy: "joiner",
            method: .deepLink,
            status: .pending
        )

        let counts = SocialInboxBadgeCounts.counts(
            from: [incomingFriend, incomingFamily],
            userId: me,
            pendingRequestsByFamily: [familyId: [pendingApproval]],
            membersByFamily: [familyId: [captain]],
            activeFamilyId: familyId
        )

        XCTAssertEqual(counts.friend, 1)
        XCTAssertEqual(counts.family, 1)
        XCTAssertEqual(counts.familyApprovals, 1)
        XCTAssertEqual(counts.familyInbox, 2)
        XCTAssertEqual(counts.total, 3)
    }
}
