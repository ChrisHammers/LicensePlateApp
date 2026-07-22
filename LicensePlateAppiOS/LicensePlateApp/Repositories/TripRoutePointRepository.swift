//
//  TripRoutePointRepository.swift
//  LicensePlateApp
//
//  GPS Step 7 — SwiftData persistence for route points. The only layer touching
//  the store for routes; local-only, no cloud writes.
//

import Foundation
import SwiftData
import CoreLocation

enum TripRoutePointRepositoryError: Error {
    case noModelContext
}

@MainActor
final class TripRoutePointRepository {
    static let shared = TripRoutePointRepository()

    private var modelContext: ModelContext?

    private init() {}

    /// Test-only construction with an explicit context.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    /// Append a batch of captured fixes for a trip. One save per batch.
    func append(points: [CLLocation], tripSessionId: UUID) throws {
        guard let modelContext else { throw TripRoutePointRepositoryError.noModelContext }
        guard !points.isEmpty else { return }
        let sessionIdString = tripSessionId.uuidString
        for point in points {
            modelContext.insert(TripRoutePointEntity(
                tripSessionId: sessionIdString,
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude,
                horizontalAccuracy: point.horizontalAccuracy,
                timestamp: point.timestamp
            ))
        }
        try modelContext.save()
    }

    /// All points for a trip, ordered by capture time.
    func points(tripSessionId: UUID) throws -> [CLLocation] {
        guard let modelContext else { throw TripRoutePointRepositoryError.noModelContext }
        let sessionIdString = tripSessionId.uuidString
        var descriptor = FetchDescriptor<TripRoutePointEntity>(
            predicate: #Predicate<TripRoutePointEntity> { $0.tripSessionId == sessionIdString }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]
        return try modelContext.fetch(descriptor).map { entity in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: entity.latitude, longitude: entity.longitude),
                altitude: 0,
                horizontalAccuracy: entity.horizontalAccuracy,
                verticalAccuracy: -1,
                timestamp: entity.timestamp
            )
        }
    }

    func deletePoints(tripSessionId: UUID) throws {
        guard let modelContext else { throw TripRoutePointRepositoryError.noModelContext }
        let sessionIdString = tripSessionId.uuidString
        try modelContext.delete(
            model: TripRoutePointEntity.self,
            where: #Predicate<TripRoutePointEntity> { $0.tripSessionId == sessionIdString }
        )
        try modelContext.save()
    }

    /// Hard sign-out: delete all local route telemetry.
    func deleteAllLocal() throws {
        guard let modelContext else { throw TripRoutePointRepositoryError.noModelContext }
        try modelContext.delete(model: TripRoutePointEntity.self)
        try modelContext.save()
    }
}
