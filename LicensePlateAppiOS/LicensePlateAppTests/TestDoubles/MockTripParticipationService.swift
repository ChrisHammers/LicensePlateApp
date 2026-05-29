//
//  MockTripParticipationService.swift
//  LicensePlateAppTests
//
//  Step 14 — Trip voluntary leave orchestration spy.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockTripParticipationService: TripParticipationServiceProtocol {

    var initiateLeaveTripCallCount = 0
    var lastLeaveSessionId: UUID?
    var lastLeaveUserId: String?
    var shouldThrow: Error?

    func initiateLeaveTrip(sessionId: UUID, userId: String) throws {
        initiateLeaveTripCallCount += 1
        lastLeaveSessionId = sessionId
        lastLeaveUserId = userId
        if let shouldThrow { throw shouldThrow }
    }
}
