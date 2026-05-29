//
//  TravelLogRepositoryProtocol.swift
//  LicensePlateApp
//
//  Protocol for travel log (completed trips) projection. Enables test doubles. Step 03 — repository layer.
//  Implementation composes TripSessionRepository and GameInstanceRepository for session list and game counts.
//

import Foundation
import SwiftData

/// Sort order for travel log entries.
enum TravelLogSort {
    case endedAtDesc
    case endedAtAsc
}

/// When true, include both ended and cancelled sessions in Travel Log. Step 07 optional.
enum TravelLogStatusFilter {
    case endedOnly
    case endedAndCancelled
}

@MainActor
protocol TravelLogRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func fetchCompletedSessions(userId: String?, limit: Int) throws -> [TripSession]
    /// - Parameter statusFilter: .endedOnly (default) or .endedAndCancelled for abandoned trips.
    func getSummaryProjections(userId: String?, sortBy: TravelLogSort, limit: Int, statusFilter: TravelLogStatusFilter) throws -> [TravelLogEntry]
}
