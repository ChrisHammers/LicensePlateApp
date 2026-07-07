//
//  TripRouteSummaryBuilderTests.swift
//  LicensePlateAppTests
//
//  GPS Step 9 — polyline simplification bounds, stats, and metadata round-trip.
//

import Foundation
import CoreLocation
import Testing
@testable import LicensePlateApp

struct TripRouteSummaryBuilderTests {

    private func fix(lat: Double, lon: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func nilForFewerThanTwoPoints() {
        #expect(TripRouteSummaryBuilder.locationMetadata(from: []) == nil)
        #expect(TripRouteSummaryBuilder.locationMetadata(from: [fix(lat: 39, lon: -104, at: 0)]) == nil)
    }

    @Test func metadataRoundTripsCoordinatesAndStats() throws {
        let points = [
            fix(lat: 39.7500, lon: -104.9900, at: 1_000),
            fix(lat: 39.7600, lon: -104.9000, at: 1_600),
            fix(lat: 39.7500, lon: -104.8000, at: 2_200)
        ]
        let metadata = try #require(TripRouteSummaryBuilder.locationMetadata(from: points))

        let coordinates = TripRouteSummaryBuilder.coordinates(from: metadata)
        #expect(coordinates.count >= 2)
        #expect(abs(coordinates.first!.latitude - 39.75) < 0.001)
        #expect(abs(coordinates.last!.longitude - (-104.80)) < 0.001)

        let duration = try #require(TripRouteSummaryBuilder.durationSeconds(from: metadata))
        #expect(duration == 1_200)

        let distance = try #require(TripRouteSummaryBuilder.distanceMeters(from: metadata))
        // Two legs of roughly 7.7 km + 8.5 km; sanity-band the sum.
        #expect(distance > 10_000 && distance < 25_000)

        #expect(metadata[TripRouteSummaryBuilder.MetadataKey.routePointCount] == "3")
    }

    @Test func douglasPeuckerDropsCollinearMiddlePoints() {
        // 11 points in a straight line east — only the endpoints survive.
        let line = (0...10).map { step in
            CLLocationCoordinate2D(latitude: 39.75, longitude: -105.0 + Double(step) * 0.01)
        }
        let simplified = TripRouteSummaryBuilder.douglasPeucker(line, toleranceMeters: 100)
        #expect(simplified.count == 2)
    }

    @Test func douglasPeuckerKeepsSignificantDetour() {
        let route = [
            CLLocationCoordinate2D(latitude: 39.75, longitude: -105.00),
            CLLocationCoordinate2D(latitude: 39.85, longitude: -104.95), // ~11 km off the direct line
            CLLocationCoordinate2D(latitude: 39.75, longitude: -104.90)
        ]
        let simplified = TripRouteSummaryBuilder.douglasPeucker(route, toleranceMeters: 100)
        #expect(simplified.count == 3)
    }

    @Test func simplifiedPolylineIsCappedAtMaximum() {
        // 1000-point zigzag that resists tolerance-based simplification.
        let points = (0..<1000).map { step in
            fix(
                lat: 39.75 + (step.isMultiple(of: 2) ? 0.01 : -0.01),
                lon: -105.0 + Double(step) * 0.002,
                at: TimeInterval(step * 30)
            )
        }
        let metadata = TripRouteSummaryBuilder.locationMetadata(from: points)
        let coordinates = TripRouteSummaryBuilder.coordinates(from: metadata)
        #expect(coordinates.count <= TripRouteSummaryBuilder.maxSimplifiedPoints)
        #expect(coordinates.count > 2)
    }

    @Test func decodeToleratesMissingOrMalformedMetadata() {
        #expect(TripRouteSummaryBuilder.coordinates(from: nil).isEmpty)
        #expect(TripRouteSummaryBuilder.coordinates(from: [:]).isEmpty)
        #expect(TripRouteSummaryBuilder.coordinates(from: ["routePolyline": "not json"]).isEmpty)
        #expect(TripRouteSummaryBuilder.distanceMeters(from: ["routeDistanceMeters": "abc"]) == nil)
    }
}
