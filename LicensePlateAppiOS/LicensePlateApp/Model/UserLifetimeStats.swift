//
//  UserLifetimeStats.swift
//  LicensePlateApp
//
//  Domain values for persisted lifetime statistics (projection over archived trips).
//

import Foundation

struct UserLifetimeStats: Sendable, Equatable {
    var totalCompletedTrips: Int
    var totalGamesPlayed: Int
    var totalDiscoveries: Int
    var totalWeightedScore: Double
    var familyOnlyTripsCount: Int
    var lastComputedAt: Date
}
