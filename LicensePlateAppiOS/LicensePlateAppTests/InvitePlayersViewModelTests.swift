//
//  InvitePlayersViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 11.5 — Invite send success/failure and selection.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct InvitePlayersViewModelTests {
    private func auth(userId: String = "owner") -> FirebaseAuthService {
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: userId, userName: "Owner", firebaseUID: userId)
        return auth
    }

    @Test func sendSelectedInvitesSucceeds() async {
        let repo = MockTripInviteRepository()
        let vm = InvitePlayersViewModel(
            mode: .sendInvites,
            tripSessionId: UUID(),
            tripName: "Trip",
            selectedUserIds: ["friend-1"],
            authService: auth(),
            tripInviteRepository: repo,
            tripSessionRepository: MockTripSessionRepository()
        )

        let success = await vm.sendSelectedInvites()
        #expect(success)
        #expect(vm.errorMessage == nil)
    }

    @Test func sendSelectedInvitesFailureSetsError() async {
        let repo = MockTripInviteRepository()
        repo.shouldThrow = true
        let vm = InvitePlayersViewModel(
            mode: .sendInvites,
            tripSessionId: UUID(),
            tripName: "Trip",
            selectedUserIds: ["friend-1"],
            authService: auth(),
            tripInviteRepository: repo,
            tripSessionRepository: MockTripSessionRepository()
        )

        let success = await vm.sendSelectedInvites()
        #expect(!success)
        #expect(vm.errorMessage != nil)
    }
}
