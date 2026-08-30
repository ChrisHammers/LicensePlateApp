//
//  TripRouteHardeningTests.swift
//  LicensePlateAppTests
//
//  v4 F-61 (FR-101): the route stays local, stays coarse at the edges, and is gated
//  structurally. (a) render gate matrix, (b) endpoint trim incl. the degenerate case,
//  (c) the local-only invariant pinned by a source scan instead of a comment.
//

import Foundation
import CoreLocation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripRouteHardeningTests {

    /// A south→north line of points along longitude 0; ~111.32 km per degree of
    /// latitude, so 0.005° ≈ 557 m. Sequential timestamps a minute apart.
    private func line(latitudes: [Double]) -> [CLLocation] {
        let start = Date(timeIntervalSince1970: 1_000_000)
        return latitudes.enumerated().map { index, latitude in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 0),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: start.addingTimeInterval(Double(index) * 60)
            )
        }
    }

    // MARK: - FR-101(a): structural render gate

    @Test func routeSectionRendersOnlyForUnrestrictedSessionsWithData() {
        let metadata = ["routePolyline": "[[0.02,0]]"]

        #expect(TripRouteRecapPolicy.showsRouteSection(
            locationMetadata: metadata, isChildRestricted: false
        ))
        // Child-restricted ⇒ no section, REGARDLESS of stored rows — rows recorded
        // before an under-13 answer must never render for a restricted session.
        #expect(!TripRouteRecapPolicy.showsRouteSection(
            locationMetadata: metadata, isChildRestricted: true
        ))
        #expect(!TripRouteRecapPolicy.showsRouteSection(
            locationMetadata: nil, isChildRestricted: false
        ))
        #expect(!TripRouteRecapPolicy.showsRouteSection(
            locationMetadata: [:], isChildRestricted: false
        ))
        #expect(!TripRouteRecapPolicy.showsRouteSection(
            locationMetadata: nil, isChildRestricted: true
        ))
    }

    // MARK: - FR-101(b): endpoint trim (OD-12 radius, proposed 1.5 km)

    @Test func endpointTrimDropsTheDrivewayRunsAndStartsThePolylineAtTheBoundary() throws {
        // Head run within 1.5 km of the first point: 0.000/0.005/0.010 (0/557/1113 m).
        // Tail run within 1.5 km of the last: 0.060/0.055/0.050. Survivors: 0.020–0.040.
        let points = line(latitudes: [0.000, 0.005, 0.010, 0.020, 0.030, 0.040, 0.050, 0.055, 0.060])

        let trimmed = TripRouteSummaryBuilder.endpointTrimmed(points)
        #expect(trimmed.map(\.coordinate.latitude) == [0.020, 0.030, 0.040])

        let metadata = try #require(TripRouteSummaryBuilder.locationMetadata(from: points))
        let coordinates = TripRouteSummaryBuilder.coordinates(from: metadata)
        // The drawn polyline starts and ends at the trimmed boundary.
        #expect(coordinates.first?.latitude == 0.020)
        #expect(coordinates.last?.latitude == 0.040)
        // Distance describes the trimmed route (~2.2 km), not the raw one (~6.7 km).
        let distance = try #require(TripRouteSummaryBuilder.distanceMeters(from: metadata))
        #expect(distance > 2_000 && distance < 2_500)
        // Raw captured count is honest telemetry and stays the untrimmed total.
        #expect(metadata[TripRouteSummaryBuilder.MetadataKey.routePointCount] == "9")
    }

    @Test func aTripEntirelyInsideTheRadiusYieldsNoRouteAtAll() {
        // Everything within 1.5 km of both endpoints — the degenerate case must
        // produce NO route section rather than a stub.
        let points = line(latitudes: [0.000, 0.004, 0.008, 0.010])
        #expect(TripRouteSummaryBuilder.endpointTrimmed(points).isEmpty)
        #expect(TripRouteSummaryBuilder.locationMetadata(from: points) == nil)
    }

    @Test func trimIsContiguousSoAMidTripPassNearHomeIsKept() {
        // The trip leaves, dips back NEAR the start point mid-route, then continues.
        // Endpoint trimming is about the trail's ENDS — the dip is trip shape and stays.
        let points = line(latitudes: [0.000, 0.020, 0.005, 0.030, 0.060])
        let trimmed = TripRouteSummaryBuilder.endpointTrimmed(points)
        #expect(trimmed.map(\.coordinate.latitude) == [0.020, 0.005, 0.030])
    }

    // MARK: - FR-101(c): local-only invariant, pinned by source scan

    /// `TripRoutePointEntity`'s header says "local-only, never synced to Firestore" —
    /// this pins it: the entity is referenced only by its allowed local files, and no
    /// file that references it carries any Firestore surface at all. Grep-shaped and
    /// build-machine-only by nature (walks the source tree via #filePath), like the
    /// AchievementEvaluatorParityTests fixture-path precedent.
    @Test func tripRoutePointEntityIsReferencedOnlyByLocalOnlyFiles() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appDir = testsDir.deletingLastPathComponent().appendingPathComponent("LicensePlateApp")
        let allowed: Set<String> = [
            "TripRoutePointEntity.swift",
            "SchemaVersions.swift",
            "TripRoutePointRepository.swift",
            "LocalPlayIdentityRepository.swift",
        ]

        var entityReferencers: Set<String> = []
        var firestoreMarkedReferencers: Set<String> = []
        let enumerator = try #require(
            FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil)
        )
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard source.contains("TripRoutePointEntity") else { continue }
            entityReferencers.insert(url.lastPathComponent)
            // API surface only — the entity's own header SAYS "never synced to
            // Firestore" in prose, which must not trip the tripwire.
            if source.contains("import FirebaseFirestore")
                || source.contains("Firestore.firestore")
                || source.contains("firestoreValue")
                || source.contains("setData(") {
                firestoreMarkedReferencers.insert(url.lastPathComponent)
            }
        }

        // Scan sanity: the walk actually found the real code.
        #expect(entityReferencers.contains("TripRoutePointRepository.swift"))
        // The invariant: no referencer outside the allowed local set…
        #expect(entityReferencers.subtracting(allowed).isEmpty)
        // …and no referencer has any Firestore surface with which to serialize it.
        #expect(firestoreMarkedReferencers.isEmpty)
    }
}
