//
//  TripEvictionDetectionPolicyTests.swift
//  LicensePlateAppTests
//
//  FR-69 (F-25), owner-found 2026-09-07: a member the server removed from a live roster
//  kept the trip on their device forever — deleting `members/{uid}` revoked the read
//  access the `participant_left` event needed to arrive. The device's only signal is a
//  permission-denied listener; these pin when that is treated as an eviction and what
//  the local outcome is.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

struct TripEvictionDetectionPolicyTests {
    @Test func liveRosterMemberDeniedForTheirOwnUidIsEvicted() {
        #expect(TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .active, listenerUserId: "u1", currentUserId: "u1",
            isOwner: false, isOnRoster: true
        ))
        #expect(TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .created, listenerUserId: "u1", currentUserId: "u1",
            isOwner: false, isOnRoster: true
        ))
    }

    @Test func everyOtherExplanationLeavesTheSessionAlone() {
        // Signed out, or a different identity now signed in.
        #expect(!TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .active, listenerUserId: "u1", currentUserId: nil,
            isOwner: false, isOnRoster: true
        ))
        #expect(!TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .active, listenerUserId: "u1", currentUserId: "u2",
            isOwner: false, isOnRoster: true
        ))
        // Trip already over.
        #expect(!TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .ended, listenerUserId: "u1", currentUserId: "u1",
            isOwner: false, isOnRoster: true
        ))
        // The owner is never removed by a sweep (their trip is ended instead).
        #expect(!TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .active, listenerUserId: "u1", currentUserId: "u1",
            isOwner: true, isOnRoster: true
        ))
        // Already off the roster — a re-run is a no-op.
        #expect(!TripEvictionDetectionPolicy.isEviction(
            sessionStatus: .active, listenerUserId: "u1", currentUserId: "u1",
            isOwner: false, isOnRoster: false
        ))
    }
}

@MainActor
struct TripParticipationServerEvictionTests {
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

    private func makeService(auth: FirebaseAuthService) -> TripParticipationService {
        TripParticipationService(
            tripSessionRepository: TripSessionRepository.shared,
            tripActivityEventRecording: TripActivityEventRecordingService(
                tripActivityEventRepository: TripActivityEventRepository.shared,
                syncCoordinator: SyncCoordinator(repository: SyncQueueRepository.shared)
            ),
            pendingTripLeaveRepository: PendingTripLeaveRepository.shared,
            authService: auth
        )
    }

    @Test func evictionRemovesTheRosterRowEndsTheLocalTripAndIsIdempotent() throws {
        let ctx = try makeContext()
        TripSessionRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)
        let service = makeService(auth: FirebaseAuthService())

        let sessionId = UUID()
        try TripSessionRepository.shared.create(session: TripSession(
            id: sessionId,
            name: "Family drive",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "kid1", role: .member, joinedAt: Date()),
            ]
        ))

        let applied = try service.applyServerEviction(
            sessionId: sessionId, listenerUserId: "kid1", currentUserId: "kid1"
        )
        #expect(applied)

        let reloaded = try TripSessionRepository.shared.session(byId: sessionId)
        #expect(reloaded?.participants.contains { $0.userId == "kid1" } == false)
        #expect(reloaded?.status == .ended)
        // Nothing is queued for sync: the server already holds the participant_left row
        // and this device can no longer write to the session anyway.
        #expect(try PendingTripLeaveRepository.shared.hasPending(sessionId: sessionId, userId: "kid1") == false)

        // The second listener's error re-runs the apply; it must be a no-op.
        #expect(try service.applyServerEviction(
            sessionId: sessionId, listenerUserId: "kid1", currentUserId: "kid1"
        ) == false)
    }

    @Test func ownerAndMismatchedIdentityAreNeverEvicted() throws {
        let ctx = try makeContext()
        TripSessionRepository.shared.setModelContext(ctx)
        PendingTripLeaveRepository.shared.setModelContext(ctx)
        TripActivityEventRepository.shared.setModelContext(ctx)
        SyncQueueRepository.shared.setModelContext(ctx)
        let service = makeService(auth: FirebaseAuthService())

        let sessionId = UUID()
        try TripSessionRepository.shared.create(session: TripSession(
            id: sessionId,
            name: "Family drive",
            status: .active,
            createdAt: Date(),
            createdBy: "owner1",
            startedAt: Date(),
            participants: [
                TripParticipant(userId: "owner1", role: .owner, joinedAt: Date()),
                TripParticipant(userId: "kid1", role: .member, joinedAt: Date()),
            ]
        ))

        #expect(try service.applyServerEviction(
            sessionId: sessionId, listenerUserId: "owner1", currentUserId: "owner1"
        ) == false)
        #expect(try service.applyServerEviction(
            sessionId: sessionId, listenerUserId: "kid1", currentUserId: "someone-else"
        ) == false)

        let reloaded = try TripSessionRepository.shared.session(byId: sessionId)
        #expect(reloaded?.status == .active)
        #expect(reloaded?.participants.count == 2)
    }
}
