//
//  TripParticipantsViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 11.5 — Passenger list projection tests.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripParticipantsViewModelTests {
    @Test func reloadBuildsPassengersAndPendingInvites() async {
        let sessionId = UUID()
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(
            TripSession(
                id: sessionId,
                name: "Road Trip",
                status: .created,
                createdBy: "owner",
                participants: [
                    TripParticipant(userId: "owner", role: .owner),
                    TripParticipant(userId: "member", role: .member)
                ]
            )
        )

        let inviteRepo = MockTripInviteRepository()
        inviteRepo.seed(
            TripInvite(
                inviteId: "inv-1",
                tripSessionId: sessionId.uuidString,
                tripName: "Road Trip",
                fromUserId: "owner",
                toUserId: "pending-user",
                status: .pending,
                createdAt: .now,
                expiresAt: .now.addingTimeInterval(3600)
            )
        )

        let vm = TripParticipantsViewModel(
            sessionId: sessionId,
            tripSessionRepository: sessionRepo,
            tripInviteRepository: inviteRepo,
            displayNamesProvider: { ids in
                var names: [String: String] = [:]
                for id in ids { names[id] = "name-\(id)" }
                return names
            }
        )

        await vm.reload()

        #expect(vm.tripName == "Road Trip")
        #expect(vm.passengers.count == 2)
        #expect(vm.passengers.first?.isCreator == true)
        #expect(vm.passengers.first?.roleLabel == "Driver".localized)
        #expect(vm.passengers.last?.roleLabel == "Passenger".localized)
        #expect(vm.pendingInviteRows.count == 1)
        #expect(vm.pendingInviteRows.first?.inviteeDisplayName == "name-pending-user")
    }
}
