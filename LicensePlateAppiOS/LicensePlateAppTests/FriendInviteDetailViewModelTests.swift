//
//  FriendInviteDetailViewModelTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

@MainActor
struct FriendInviteDetailViewModelTests {

    @Test func storesInviteId() {
        let vm = FriendInviteDetailViewModel(inviteId: "invite-123")
        #expect(vm.inviteId == "invite-123")
        #expect(!vm.hasAccepted)
        #expect(vm.user == nil)
    }
}
