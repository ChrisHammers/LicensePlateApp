//
//  MockTravelLogRepository.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for TravelLogRepositoryProtocol. Configurable return values; optional throw.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTravelLogRepository: TravelLogRepositoryProtocol {
    private var context: ModelContext?
    var completedSessionsToReturn: [TripSession] = []
    var summaryProjectionsToReturn: [TravelLogEntry] = []
    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {
        self.context = context
    }

    func fetchCompletedSessions(userId: String?, limit: Int) throws -> [TripSession] {
        if shouldThrow { throw NSError(domain: "MockTravelLogRepository", code: -1, userInfo: nil) }
        return completedSessionsToReturn
    }

    func getSummaryProjections(userId: String?, sortBy: TravelLogSort, limit: Int, statusFilter: TravelLogStatusFilter) throws -> [TravelLogEntry] {
        if shouldThrow { throw NSError(domain: "MockTravelLogRepository", code: -1, userInfo: nil) }
        return summaryProjectionsToReturn
    }

    /// Test helper: set entries for getSummaryProjections
    func setSummaryProjections(_ entries: [TravelLogEntry]) {
        summaryProjectionsToReturn = entries
    }

    /// Test helper: set completed sessions
    func setCompletedSessions(_ sessions: [TripSession]) {
        completedSessionsToReturn = sessions
    }
}
