//
//  FamilyInviteDetailViewModelTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

@MainActor
struct FamilyInviteDetailViewModelTests {

    @Test func storesIdsAndStartsIdle() {
        let vm = FamilyInviteDetailViewModel(inviteId: "invite-1", familyId: "family-1")
        #expect(vm.inviteId == "invite-1")
        #expect(vm.familyId == "family-1")
        #expect(!vm.hasAccepted)
        #expect(vm.processingAction == nil)
        #expect(!vm.isProcessing)
        #expect(vm.errorMessage == nil)
    }
}
