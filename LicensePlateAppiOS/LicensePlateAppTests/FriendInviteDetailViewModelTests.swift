//
//  FriendInviteDetailViewModelTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class FriendInviteDetailViewModelTests: XCTestCase {

    @MainActor
    func testStoresInviteId() {
        let vm = FriendInviteDetailViewModel(inviteId: "invite-123")
        XCTAssertEqual(vm.inviteId, "invite-123")
        XCTAssertFalse(vm.hasAccepted)
        XCTAssertNil(vm.user)
    }
}
