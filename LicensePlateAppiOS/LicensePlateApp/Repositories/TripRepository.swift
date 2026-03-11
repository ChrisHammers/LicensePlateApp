//
//  TripRepository.swift
//  LicensePlateApp
//
//  Step 07 — Fetch legacy Trip by id for Travel Log summary (LegacyTripAdapter).
//

import Foundation
import SwiftData
import Combine

@MainActor
final class TripRepository: ObservableObject, TripRepositoryProtocol {

    static let shared = TripRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func get(byId id: UUID) throws -> Trip? {
        guard let ctx = modelContext else { throw TripRepositoryError.noModelContext }
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate<Trip> { trip in trip.id == id }
        )
        descriptor.fetchLimit = 1
        return try ctx.fetch(descriptor).first
    }
}

enum TripRepositoryError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "Model context not set"
        }
    }
}
