//
//  TripParticipationServiceTests.swift
//  LicensePlateAppTests
//
//  Step 14 — TripParticipationService: pending row, roster removal, participant_left + queue.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripParticipationServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    @Test func initiateLeaveTripInsertsPendingRemovesParticipantAndRecordsEvent() async throws {
        let ctx = try makeContext()
        TripSessionRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)

        let coordinator = SyncCoordinator(repository: SyncQueueRepository.shared)
        let recording = TripActivityEventRecordingService(
            tripActivityEventRepository: TripActivityEventRepository.shared,
            syncCoordinator: coordinator
        )

        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "joiner1", userName: "J", firebaseUID: "joiner1")

        let service = TripParticipationService(
            tripSessionRepository: TripSessionRepository.shared,
            tripActivityEventRecording: recording,
            pendingTripLeaveRepository: PendingTripLeaveRepository.shared,
            authService: auth
        )

        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Shared",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "joiner1", role: .member, joinedAt: Date())
            ]
        )
        try TripSessionRepository.shared.create(session: session)

        try service.initiateLeaveTrip(sessionId: sessionId, userId: "joiner1")

        #expect(try PendingTripLeaveRepository.shared.hasPending(sessionId: sessionId, userId: "joiner1") == true)
        let reloaded = try TripSessionRepository.shared.session(byId: sessionId)
        #expect(reloaded?.participants.contains { $0.userId == "joiner1" } == false)

        let events = try TripActivityEventRepository.shared.events(sessionId: sessionId, limit: nil)
        let left = events.first { $0.kind == .participantLeft }
        #expect(left != nil)
        #expect(left?.payload?[TripActivityEventPayloadKey.leaveReason] == "voluntary")
        let pending = try SyncQueueRepository.shared.fetchPending(limit: 10)
        #expect(!pending.isEmpty)
    }

    @Test func initiateLeaveTripThrowsForOwner() async throws {
        let ctx = try makeContext()
        TripSessionRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)
        let recording = TripActivityEventRecordingService(
            tripActivityEventRepository: TripActivityEventRepository.shared,
            syncCoordinator: SyncCoordinator(repository: SyncQueueRepository.shared)
        )
        let auth = FirebaseAuthService()
        auth.currentUser = AppUser(id: "owner1", userName: "O", firebaseUID: "owner1")
        let service = TripParticipationService(
            tripSessionRepository: TripSessionRepository.shared,
            tripActivityEventRecording: recording,
            pendingTripLeaveRepository: PendingTripLeaveRepository.shared,
            authService: auth
        )
        let sessionId = UUID()
        let session = TripSession(
            id: sessionId,
            name: "Mine",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [TripParticipant(userId: "owner1", role: .owner, joinedAt: Date())]
        )
        try TripSessionRepository.shared.create(session: session)

        var caughtOwnerError = false
        do {
            try service.initiateLeaveTrip(sessionId: sessionId, userId: "owner1")
        } catch TripParticipationServiceError.tripOwnerCannotLeaveViaLeaveAction {
            caughtOwnerError = true
        } catch {
            Issue.record("Expected tripOwnerCannotLeaveViaLeaveAction, got \(error)")
        }
        #expect(caughtOwnerError)
    }
}
