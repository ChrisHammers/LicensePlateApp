//
//  LegacyTripAdapterTests.swift
//  LicensePlateAppTests
//
//  Step 01 — mapping from legacy Trip.foundRegions to TripSession + discoveries; read-only, migration-safe.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

struct LegacyTripAdapterTests {

    /// Create an in-memory container and a Trip for adapter tests (read-only; no persistence needed for adapter output).
    private func makeTrip(
        name: String = "Test Trip",
        createdBy: String? = "user1",
        foundRegions: [FoundRegion] = []
    ) throws -> Trip {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, configurations: config)
        let context = ModelContext(container)
        let trip = Trip(
            name: name,
            foundRegions: foundRegions,
            createdBy: createdBy
        )
        context.insert(trip)
        try context.save()
        return trip
    }

    @Test @MainActor func mapEmptyTripToSession() async throws {
        let trip = try makeTrip(name: "Empty", foundRegions: [])
        let result = LegacyTripAdapter.adapt(trip)

        #expect(result.session.name == "Empty")
        #expect(result.session.legacyTripId == trip.id)
        #expect(result.session.status == .draft)
        #expect(result.session.mode == .solo)
        #expect(result.discoveries.isEmpty)
        #expect(result.credits.isEmpty)
    }

    @Test @MainActor func mapTripWithFoundRegionsNoFoundBy() async throws {
        let regions = [
            FoundRegion(regionID: "us-ca", foundAt: .now, inputMethod: .list, foundBy: nil),
            FoundRegion(regionID: "us-ny", foundAt: .now, inputMethod: .voice, foundBy: nil)
        ]
        let trip = try makeTrip(createdBy: "solo_user", foundRegions: regions)
        let result = LegacyTripAdapter.adapt(trip)

        #expect(result.session.mode == .solo)
        #expect(result.discoveries.count == 2)
        #expect(result.credits.count == 2)
        let targetIds = Set(result.discoveries.map(\.targetId))
        #expect(targetIds.contains("us-ca"))
        #expect(targetIds.contains("us-ny"))
        for d in result.discoveries {
            #expect(d.participantId == "solo_user")
        }
        for c in result.credits {
            #expect(c.creditType == .full)
        }
    }

    @Test @MainActor func mapTripWithFoundByMultipleParticipants() async throws {
        let regions = [
            FoundRegion(regionID: "us-ca", foundAt: .now, inputMethod: .list, foundBy: "user1"),
            FoundRegion(regionID: "us-ny", foundAt: .now, inputMethod: .voice, foundBy: "user2")
        ]
        let trip = try makeTrip(createdBy: "user1", foundRegions: regions)
        let result = LegacyTripAdapter.adapt(trip)

        #expect(result.session.mode == .collaborative)
        #expect(result.discoveries.count == 2)
        #expect(Set(result.session.participants.map(\.userId)) == ["user1", "user2"])
        let byUser1 = result.discoveries.first { $0.participantId == "user1" }
        let byUser2 = result.discoveries.first { $0.participantId == "user2" }
        #expect(byUser1?.targetId == "us-ca")
        #expect(byUser2?.targetId == "us-ny")
    }

    @Test @MainActor func adapterIsReadOnlyNoPersistence() async throws {
        let trip = try makeTrip(name: "ReadOnly", foundRegions: [])
        let result = LegacyTripAdapter.adapt(trip)

        // Adapter returns new in-memory objects; no Trip or SwiftData types are mutated
        #expect(result.session.legacyTripId == trip.id)
        #expect(result.session.name == "ReadOnly")
        // Session and game instance are new objects, not the Trip
        #expect(result.session.id == trip.id)
        #expect(result.gameInstance.sessionId == trip.id)
    }

    @Test @MainActor func endedTripMapsToEndedStatus() async throws {
        let trip = try makeTrip(name: "Ended", foundRegions: [])
        trip.isTripEnded = true
        trip.tripEndedAt = Date()
        trip.tripEndedBy = "user1"

        let result = LegacyTripAdapter.adapt(trip)
        #expect(result.session.status == .ended)
        #expect(result.session.endedAt != nil)
        #expect(result.session.endedBy == "user1")
    }
}
