//
//  TravelLogRepositoryProtocol.swift
//  LicensePlateApp
//
//  Protocol for travel log (completed trips) projection. Enables test doubles. Step 03 — repository layer.
//

import Foundation
import SwiftData

/// Sort order for travel log entries.
enum TravelLogSort {
    case endedAtDesc
    case endedAtAsc
}

@MainActor
protocol TravelLogRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)

    func fetchCompletedSessions(userId: String?, limit: Int) throws -> [TripSession]
    func getSummaryProjections(userId: String?, sortBy: TravelLogSort, limit: Int) throws -> [TravelLogEntry]
}
