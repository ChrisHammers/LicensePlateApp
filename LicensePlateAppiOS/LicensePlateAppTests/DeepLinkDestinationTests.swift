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
        let c = DeepLinkDestination.familyPendingApprovals(familyId: "fam-1")
        let d = DeepLinkDestination.familyHome(familyId: "fam-1")
        XCTAssertEqual(a.id, "friend-abc")
        XCTAssertEqual(b.id, "family-x-y")
        XCTAssertEqual(c.id, "family-pending-fam-1")
        XCTAssertEqual(d.id, "family-home-fam-1")
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

    func testNotificationUserInfoFamilyJoinRequestFallback() {
        let userInfo: [AnyHashable: Any] = [
            "type": "family_join_request",
            "familyId": "fam-9"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .familyPendingApprovals(familyId: "fam-9"))
    }

    func testNotificationUserInfoFamilyJoinApprovedFallback() {
        let userInfo: [AnyHashable: Any] = [
            "type": "family_join_approved",
            "familyId": "fam-9"
        ]
        let destination = DeepLinkHandler.destination(fromNotificationUserInfo: userInfo)
        XCTAssertEqual(destination, .familyHome(familyId: "fam-9"))
    }

    func testHandleURLFamilyPendingAndHome() {
        let pending = DeepLinkHandler.shared.handleURL(
            URL(string: "roadtrip-royale://family/fam-1/pending")!
        )
        XCTAssertEqual(pending, .familyPendingApprovals(familyId: "fam-1"))

        let home = DeepLinkHandler.shared.handleURL(
            URL(string: "roadtrip-royale://family/fam-1")!
        )
        XCTAssertEqual(home, .familyHome(familyId: "fam-1"))
    }

    func testNotificationUserInfoIgnoresUnknownType() {
        let userInfo: [AnyHashable: Any] = [
            "type": "milestone",
            "inviteId": "x"
        ]
        XCTAssertNil(DeepLinkHandler.destination(fromNotificationUserInfo: userInfo))
    }
}
