//
//  TripRepositoryProtocol.swift
//  LicensePlateApp
//
//  Step 07 — Protocol for fetching legacy Trip by id (Travel Log summary loading).
//

import Foundation
import SwiftData

@MainActor
protocol TripRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    func get(byId id: UUID) throws -> Trip?
    /// Active legacy trips (not ended) whose id is not in the given set (e.g. session ids already shown).
    func fetchActiveLegacyTrips(excludingSessionIds: Set<UUID>) throws -> [Trip]
}
