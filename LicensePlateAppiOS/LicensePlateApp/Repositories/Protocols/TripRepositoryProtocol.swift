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
}
