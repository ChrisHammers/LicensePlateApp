//
//  MockTripRepository.swift
//  LicensePlateAppTests
//
//  Step 13 — Test double for TripRepositoryProtocol. In-memory legacy Trip lookup; configurable errors.
//

import Foundation
import SwiftData
@testable import LicensePlateApp

@MainActor
final class MockTripRepository: TripRepositoryProtocol {
    private var trips: [UUID: Trip] = [:]
    private var context: ModelContext?
    var shouldThrow = false

    func setModelContext(_ context: ModelContext) {
        self.context = context
    }

    func get(byId id: UUID) throws -> Trip? {
        if shouldThrow { throw NSError(domain: "MockTripRepository", code: -1, userInfo: nil) }
        return trips[id]
    }

    func fetchActiveLegacyTrips(excludingSessionIds: Set<UUID>) throws -> [Trip] {
        if shouldThrow { throw NSError(domain: "MockTripRepository", code: -1, userInfo: nil) }
        return trips.values.filter { trip in
            guard trip.isTripEnded == false else { return false }
            return !excludingSessionIds.contains(trip.id)
        }
    }

    /// Test helper: seed a legacy Trip (caller must have created it, e.g. in test container)
    func seed(_ trip: Trip) {
        trips[trip.id] = trip
    }

    func clear() {
        trips.removeAll()
    }
}
