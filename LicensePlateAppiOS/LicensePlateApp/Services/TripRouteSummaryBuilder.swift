//
//  TripRouteSummaryBuilder.swift
//  LicensePlateApp
//
//  GPS Step 9 — pure route summarization for the trip recap. Simplifies the persisted
//  route (Douglas-Peucker) and packs polyline + stats into TripSummary.locationMetadata.
//  No persistence, no logging; coordinates stay in the metadata dict for local rendering.
//

import Foundation
import CoreLocation

enum TripRouteSummaryBuilder {

    enum MetadataKey {
        /// JSON array of [latitude, longitude] pairs (simplified, capture order).
        static let routePolyline = "routePolyline"
        static let routeDistanceMeters = "routeDistanceMeters"
        static let routeDurationSeconds = "routeDurationSeconds"
        /// Raw captured point count before simplification.
        static let routePointCount = "routePointCount"
    }

    /// Simplified polyline never exceeds this many points.
    static let maxSimplifiedPoints = 200

    /// FR-101(b) (v4 F-61): OD-12 endpoint-privacy radius (proposed 1.5 km implemented
    /// as the default; owner-adjustable constant). A road-trip trail must not begin in
    /// the family's driveway.
    static let endpointTrimRadiusMeters: Double = 1_500

    // MARK: - Build (points → metadata)

    /// FR-101(b): drops the contiguous run of points within the radius of the FIRST
    /// recorded point and the contiguous run within the radius of the LAST, so the
    /// drawn polyline starts and ends at the trimmed boundary. Deliberately contiguous:
    /// a mid-trip pass NEAR the start point is trip shape, not an endpoint, and stays.
    static func endpointTrimmed(_ points: [CLLocation]) -> [CLLocation] {
        guard let first = points.first, let last = points.last else { return [] }
        var startIndex = 0
        while startIndex < points.count,
              points[startIndex].distance(from: first) <= endpointTrimRadiusMeters {
            startIndex += 1
        }
        var endIndex = points.count - 1
        while endIndex >= 0,
              points[endIndex].distance(from: last) <= endpointTrimRadiusMeters {
            endIndex -= 1
        }
        guard startIndex <= endIndex else { return [] }
        return Array(points[startIndex...endIndex])
    }

    /// nil when there aren't enough points to describe a route — including the
    /// FR-101(b) degenerate case (whole trip inside the trim radius): no route
    /// section at all rather than a stub.
    static func locationMetadata(from rawPoints: [CLLocation]) -> [String: String]? {
        let points = endpointTrimmed(rawPoints)
        guard points.count >= 2 else { return nil }

        let distance = zip(points, points.dropFirst()).reduce(0.0) { total, pair in
            total + pair.1.distance(from: pair.0)
        }
        let duration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)

        var simplified = douglasPeucker(points.map(\.coordinate), toleranceMeters: 100)
        if simplified.count > maxSimplifiedPoints {
            let stride = Double(simplified.count) / Double(maxSimplifiedPoints)
            simplified = (0..<maxSimplifiedPoints).map { simplified[Int(Double($0) * stride)] }
        }

        let pairs = simplified.map { [round5($0.latitude), round5($0.longitude)] }
        guard let polylineData = try? JSONEncoder().encode(pairs),
              let polylineJSON = String(data: polylineData, encoding: .utf8) else {
            return nil
        }

        return [
            MetadataKey.routePolyline: polylineJSON,
            MetadataKey.routeDistanceMeters: String(Int(distance.rounded())),
            MetadataKey.routeDurationSeconds: String(Int(max(0, duration).rounded())),
            MetadataKey.routePointCount: String(rawPoints.count)
        ]
    }

    // MARK: - Read (metadata → view data)

    static func coordinates(from metadata: [String: String]?) -> [CLLocationCoordinate2D] {
        guard let json = metadata?[MetadataKey.routePolyline],
              let data = json.data(using: .utf8),
              let pairs = try? JSONDecoder().decode([[Double]].self, from: data) else {
            return []
        }
        return pairs.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    static func distanceMeters(from metadata: [String: String]?) -> Double? {
        metadata?[MetadataKey.routeDistanceMeters].flatMap(Double.init)
    }

    static func durationSeconds(from metadata: [String: String]?) -> Double? {
        metadata?[MetadataKey.routeDurationSeconds].flatMap(Double.init)
    }

    // MARK: - Simplification

    /// Iterative Douglas-Peucker over coordinates, tolerance in meters.
    static func douglasPeucker(_ coordinates: [CLLocationCoordinate2D], toleranceMeters: Double) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }

        var keep = [Bool](repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        var stack: [(Int, Int)] = [(0, coordinates.count - 1)]

        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance = 0.0
            var maxIndex = start
            for index in (start + 1)..<end {
                let distance = perpendicularDistanceMeters(
                    of: coordinates[index],
                    fromSegment: coordinates[start],
                    to: coordinates[end]
                )
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = index
                }
            }
            if maxDistance > toleranceMeters {
                keep[maxIndex] = true
                stack.append((start, maxIndex))
                stack.append((maxIndex, end))
            }
        }

        return coordinates.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// Perpendicular distance using a local flat-earth approximation — fine at route scale.
    private static func perpendicularDistanceMeters(
        of point: CLLocationCoordinate2D,
        fromSegment start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(start.latitude * .pi / 180)

        let px = (point.longitude - start.longitude) * metersPerDegreeLon
        let py = (point.latitude - start.latitude) * metersPerDegreeLat
        let ex = (end.longitude - start.longitude) * metersPerDegreeLon
        let ey = (end.latitude - start.latitude) * metersPerDegreeLat

        let segmentLengthSquared = ex * ex + ey * ey
        guard segmentLengthSquared > 0 else {
            return (px * px + py * py).squareRoot()
        }
        let t = max(0, min(1, (px * ex + py * ey) / segmentLengthSquared))
        let dx = px - t * ex
        let dy = py - t * ey
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func round5(_ value: Double) -> Double {
        (value * 100_000).rounded() / 100_000
    }
}

/// FR-101(a) (v4 F-61): the recap's route section is STRUCTURALLY gated — the
/// child-restriction resolver term decides, never data presence alone, so route rows
/// recorded before an under-13 answer (or on a device whose posture later flipped)
/// can never render for a restricted session.
enum TripRouteRecapPolicy {
    static func showsRouteSection(
        locationMetadata: [String: String]?,
        isChildRestricted: Bool
    ) -> Bool {
        guard !isChildRestricted else { return false }
        guard let metadata = locationMetadata, !metadata.isEmpty else { return false }
        return true
    }
}
