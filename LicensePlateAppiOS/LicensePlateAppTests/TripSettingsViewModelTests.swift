//
//  TripSettingsViewModelTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.3.1 — TripSettingsViewModel routes trip delete to TripSessionLifecycleService only.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripSettingsViewModelTests {

    @Test func deleteTripUsesCancelSessionAndDoesNotResetGame() throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let tripLifecycle = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = TripSettingsViewModel(
            session: session,
            tripSessionRepository: sessionRepo,
            lifecycleService: tripLifecycle,
            authService: auth
        )

        try viewModel.deleteTrip()

        #expect(tripLifecycle.cancelSessionCallCount == 1)
        #expect(tripLifecycle.cancelSessionIds == [sessionId])
    }

    @Test func endTripUsesTripLifecycleService() throws {
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "T",
            status: .active,
            createdAt: Date(),
            createdBy: "u1",
            startedAt: Date(),
            participants: []
        )
        let sessionRepo = MockTripSessionRepository()
        sessionRepo.seed(session)
        let tripLifecycle = MockTripSessionLifecycleService()
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "u1", userName: "U", firebaseUID: "u1")

        let viewModel = TripSettingsViewModel(
            session: session,
            tripSessionRepository: sessionRepo,
            lifecycleService: tripLifecycle,
            authService: auth
        )

        try viewModel.endTrip()

        #expect(tripLifecycle.endTripCallCount == 1)
        #expect(tripLifecycle.endTripSessionIds == [sessionId])
    }
}
