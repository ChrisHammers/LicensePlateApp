//
//  DeepLinkDestinationTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

@MainActor
final class DeepLinkDestinationTests: XCTestCase {

    func testIdentifiableIdsAreStable() {
        let a = DeepLinkDestination.friendInvite(inviteId: "abc")
        let b = DeepLinkDestination.familyInvite(inviteId: "x", familyId: "y")
        XCTAssertEqual(a.id, "friend-abc")
        XCTAssertEqual(b.id, "family-x-y")
    }

    func testNotificationUserInfoPrefersDeepLink() {
        let userInfo: [AnyHashable: Any] = [
            "type": "friend_invite",
            "inviteId": "wrong-id",
            "deepLink": "roadtrip-royale://invite/friend?inviteId=from-link"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .friendInvite(inviteId: "from-link"))
    }

    func testNotificationUserInfoFriendInviteFallback() {
        let userInfo: [AnyHashable: Any] = [
            "type": "friend_invite",
            "inviteId": "friend-1"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .friendInvite(inviteId: "friend-1"))
    }

    func testNotificationUserInfoFamilyInviteFallback() {
        let userInfo: [AnyHashable: Any] = [
            "type": "family_invite",
            "inviteId": "inv-1",
            "familyId": "fam-1"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .familyInvite(inviteId: "inv-1", familyId: "fam-1"))
    }

    func testNotificationUserInfoTripInviteFallback() {
        let userInfo: [AnyHashable: Any] = [
            "type": "trip_invite",
            "inviteId": "trip-inv-1"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .tripInvite(inviteId: "trip-inv-1"))
    }

    func testNotificationUserInfoIgnoresUnknownType() {
        let userInfo: [AnyHashable: Any] = [
            "type": "milestone",
            "inviteId": "x"
        ]
        XCTAssertNil(DeepLinkHandler.destination(fromNotificationUserInfo: userInfo))
    }
}
