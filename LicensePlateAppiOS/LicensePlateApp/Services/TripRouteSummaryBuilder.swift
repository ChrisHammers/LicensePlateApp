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

    // MARK: - Build (points → metadata)

    /// nil when there aren't enough points to describe a route.
    static func locationMetadata(from points: [CLLocation]) -> [String: String]? {
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
            MetadataKey.routePointCount: String(points.count)
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
