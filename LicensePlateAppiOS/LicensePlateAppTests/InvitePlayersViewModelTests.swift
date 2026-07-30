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
        let sessionId = UUID()
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(
            TripSession(
                id: sessionId,
                name: "Trip",
                status: .created,
                createdBy: "owner",
                participants: [TripParticipant(userId: "owner", role: .owner)]
            )
        )
        let repo = MockTripInviteRepository()
        let vm = InvitePlayersViewModel(
            mode: .sendInvites,
            tripSessionId: sessionId,
            tripName: "Trip",
            selectedUserIds: ["friend-1"],
            authService: auth(),
            tripInviteRepository: repo,
            tripSessionRepository: sessionRepo
        )

        let success = await vm.sendSelectedInvites()
        #expect(success)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isSubmitting)
    }

    @Test func sendSelectedInvitesFailureSetsError() async {
        let sessionId = UUID()
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(
            TripSession(
                id: sessionId,
                name: "Trip",
                status: .created,
                createdBy: "owner",
                participants: [TripParticipant(userId: "owner", role: .owner)]
            )
        )
        let repo = MockTripInviteRepository()
        repo.shouldThrow = true
        let vm = InvitePlayersViewModel(
            mode: .sendInvites,
            tripSessionId: sessionId,
            tripName: "Trip",
            selectedUserIds: ["friend-1"],
            authService: auth(),
            tripInviteRepository: repo,
            tripSessionRepository: sessionRepo
        )

        let success = await vm.sendSelectedInvites()
        #expect(!success)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isSubmitting)
    }

    @Test func sendSelectedInvitesRejectsNonDriver() async {
        let sessionId = UUID()
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(
            TripSession(
                id: sessionId,
                name: "Trip",
                status: .active,
                createdBy: "owner",
                participants: [
                    TripParticipant(userId: "owner", role: .owner),
                    TripParticipant(userId: "member", role: .member)
                ]
            )
        )
        let repo = MockTripInviteRepository()
        let vm = InvitePlayersViewModel(
            mode: .sendInvites,
            tripSessionId: sessionId,
            tripName: "Trip",
            selectedUserIds: ["friend-1"],
            authService: auth(userId: "member"),
            tripInviteRepository: repo,
            tripSessionRepository: sessionRepo
        )

        let success = await vm.sendSelectedInvites()
        #expect(!success)
        #expect(vm.errorMessage == "Only the Driver can invite passengers.".localized)
        #expect(repo.sendTripInviteCallCount == 0)
    }
}
