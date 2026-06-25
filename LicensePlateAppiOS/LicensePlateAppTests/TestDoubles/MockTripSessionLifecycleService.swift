//
//  MockTripSessionLifecycleService.swift
//  LicensePlateAppTests
//
//  Step 04 — Test double for TripSessionLifecycleServiceProtocol. Records calls for verification.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockTripSessionLifecycleService: TripSessionLifecycleServiceProtocol {
    var startTripCallCount = 0
    var startTripSessionIds: [UUID] = []
    var startTripActorIds: [String] = []

    var endTripCallCount = 0
    var endTripSessionIds: [UUID] = []
    var cancelSessionCallCount = 0
    var cancelSessionIds: [UUID] = []

    var shouldThrow = false

    func startTrip(sessionId: UUID, actorId: String) throws {
        if shouldThrow { throw NSError(domain: "MockLifecycleService", code: -1, userInfo: nil) }
        startTripCallCount += 1
        startTripSessionIds.append(sessionId)
        startTripActorIds.append(actorId)
    }

    func endTrip(sessionId: UUID, endedBy: String?) throws {
        if shouldThrow { throw NSError(domain: "MockLifecycleService", code: -1, userInfo: nil) }
        endTripCallCount += 1
        endTripSessionIds.append(sessionId)
    }

    func cancelSession(sessionId: UUID, cancelledBy: String?) throws {
        if shouldThrow { throw NSError(domain: "MockLifecycleService", code: -1, userInfo: nil) }
        cancelSessionCallCount += 1
        cancelSessionIds.append(sessionId)
    }

    func applyRemoteTripEnded(sessionId: UUID, endedBy: String?, endedAt: Date?) throws -> Bool {
        if shouldThrow { throw NSError(domain: "MockLifecycleService", code: -1, userInfo: nil) }
        return false
    }

    func reconcileRemoteTripEndedFromEventLog(userId: String?) throws -> [TripEndedRemotelyInfo] {
        if shouldThrow { throw NSError(domain: "MockLifecycleService", code: -1, userInfo: nil) }
        return []
    }
}
