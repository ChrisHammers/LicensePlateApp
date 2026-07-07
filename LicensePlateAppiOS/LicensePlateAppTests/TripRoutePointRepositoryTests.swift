//
//  TripRoutePointRepositoryTests.swift
//  LicensePlateAppTests
//
//  GPS Step 7 — route point persistence round-trip in an in-memory V21 container.
//

import Foundation
import CoreLocation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct TripRoutePointRepositoryTests {

    private func makeRepository() throws -> TripRoutePointRepository {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        return TripRoutePointRepository(modelContext: ModelContext(container))
    }

    private func fix(lat: Double, lon: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func appendAndFetchRoundTripsOrdered() throws {
        let repo = try makeRepository()
        let sessionId = UUID()
        // Appended out of order; fetch must sort by timestamp.
        try repo.append(points: [fix(lat: 40.0, lon: -105.0, at: 200)], tripSessionId: sessionId)
        try repo.append(points: [fix(lat: 39.0, lon: -104.0, at: 100)], tripSessionId: sessionId)

        let points = try repo.points(tripSessionId: sessionId)

        #expect(points.count == 2)
        #expect(points[0].coordinate.latitude == 39.0)
        #expect(points[1].coordinate.latitude == 40.0)
        #expect(points[0].timestamp == Date(timeIntervalSince1970: 100))
    }

    @Test func pointsAreScopedToSession() throws {
        let repo = try makeRepository()
        let sessionA = UUID()
        let sessionB = UUID()
        try repo.append(points: [fix(lat: 39.0, lon: -104.0, at: 100)], tripSessionId: sessionA)
        try repo.append(points: [fix(lat: 41.0, lon: -106.0, at: 100)], tripSessionId: sessionB)

        #expect(try repo.points(tripSessionId: sessionA).count == 1)
        #expect(try repo.points(tripSessionId: sessionB).count == 1)
    }

    @Test func deleteRemovesOnlyThatSessionsPoints() throws {
        let repo = try makeRepository()
        let sessionA = UUID()
        let sessionB = UUID()
        try repo.append(points: [fix(lat: 39.0, lon: -104.0, at: 100)], tripSessionId: sessionA)
        try repo.append(points: [fix(lat: 41.0, lon: -106.0, at: 100)], tripSessionId: sessionB)

        try repo.deletePoints(tripSessionId: sessionA)

        #expect(try repo.points(tripSessionId: sessionA).isEmpty)
        #expect(try repo.points(tripSessionId: sessionB).count == 1)
    }

    @Test func emptyAppendIsNoOp() throws {
        let repo = try makeRepository()
        let sessionId = UUID()
        try repo.append(points: [], tripSessionId: sessionId)
        #expect(try repo.points(tripSessionId: sessionId).isEmpty)
    }
}
