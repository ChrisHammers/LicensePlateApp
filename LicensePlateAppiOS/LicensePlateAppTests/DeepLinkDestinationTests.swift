//
//  DeepLinkDestinationTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class DeepLinkDestinationTests: XCTestCase {

    func testIdentifiableIdsAreStable() {
        let a = DeepLinkDestination.friendInvite(inviteId: "abc")
        let b = DeepLinkDestination.familyInvite(inviteId: "x", familyId: "y")
        XCTAssertEqual(a.id, "friend-abc")
        XCTAssertEqual(b.id, "family-x-y")
    }
}
