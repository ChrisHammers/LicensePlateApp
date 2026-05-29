//
//  FriendsHubInviteFilterTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class FriendsHubInviteFilterTests: XCTestCase {

    func testSplitIncomingOutgoing() {
        let exp = Date().addingTimeInterval(86400)
        let u1 = "user-a"
        let u2 = "user-b"

        let incoming = Invite(
            inviteId: "i1",
            type: .friend,
            fromUserId: u2,
            toUserId: u1,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let outgoing = Invite(
            inviteId: "i2",
            type: .friend,
            fromUserId: u1,
            toUserId: u2,
            status: .pending,
            method: .search,
            expiresAt: exp
        )
        let family = Invite(
            inviteId: "i3",
            type: .family,
            fromUserId: u2,
            toUserId: u1,
            familyId: "fam",
            status: .pending,
            method: .search,
            expiresAt: exp
        )

        let split = FriendsHubInviteFilter.splitFriendInvites([incoming, outgoing, family], userId: u1)

        XCTAssertEqual(split.incoming.map(\.inviteId), ["i1"])
        XCTAssertEqual(split.outgoing.map(\.inviteId), ["i2"])
    }
}
