//
//  MockTripCanonicalRemoteSync.swift
//  LicensePlateAppTests
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockTripCanonicalRemoteSync: TripCanonicalRemoteSyncing {
    var removeParticipantAsOwnerCallCount = 0
    var lastRemovedUserId: String?
    var shouldThrow = false

    func publishFullSession(sessionId: UUID) async throws {}
    func appendEventToRemote(_ event: TripActivityEvent) async throws -> GameplayEventAppendOutcome {
        _ = event
        return .accepted(lateReplay: false)
    }
    func bootstrapMemberSession(sessionId: UUID) async throws {}
    func startIncrementalListeningIfNeeded(sessionId: UUID) {}
    func markTripCancelledRemote(sessionId: UUID) async throws {}

    func removeParticipantAsOwner(sessionId: UUID, removedUserId: String) async throws {
        removeParticipantAsOwnerCallCount += 1
        lastRemovedUserId = removedUserId
        if shouldThrow {
            throw NSError(domain: "MockTripCanonicalRemoteSync", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "mock remove failed"
            ])
        }
    }
}
