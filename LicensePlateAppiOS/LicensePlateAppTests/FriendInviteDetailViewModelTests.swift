//
//  FriendInviteDetailViewModelTests.swift
//  LicensePlateAppTests
//

import XCTest
@testable import LicensePlateApp

final class FriendInviteDetailViewModelTests: XCTestCase {

    @MainActor
    func testStoresInviteId() {
        var vm: FriendInviteDetailViewModel? = FriendInviteDetailViewModel(inviteId: "invite-123")
        XCTAssertEqual(vm?.inviteId, "invite-123")
        XCTAssertFalse(vm?.hasAccepted ?? true)
        XCTAssertNil(vm?.user)
        vm = nil
    }
}
