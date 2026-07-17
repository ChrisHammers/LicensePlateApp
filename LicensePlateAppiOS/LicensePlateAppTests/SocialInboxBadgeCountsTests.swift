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
            familyId: "family-1",
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
        XCTAssertEqual(counts.total, 2)
    }

    func testEmptyWhenNoPendingIncoming() {
        let counts = SocialInboxBadgeCounts.counts(from: [], userId: me)
        XCTAssertEqual(counts, SocialInboxBadgeCounts.Counts(friend: 0, family: 0))
    }
}
