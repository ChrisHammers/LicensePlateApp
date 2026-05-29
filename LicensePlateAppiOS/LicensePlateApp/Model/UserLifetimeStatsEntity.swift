//
//  UserLifetimeStatsEntity.swift
//  LicensePlateApp
//
//  SwiftData cache row for profile lifetime stats (Schema V17+).
//

import Foundation
import SwiftData

@Model
final class UserLifetimeStatsEntity {
    @Attribute(.unique) var userId: String
    var totalCompletedTrips: Int
    var totalGamesPlayed: Int
    var totalDiscoveries: Int
    var totalWeightedScore: Double
    var familyOnlyTripsCount: Int
    var lastComputedAt: Date

    init(
        userId: String,
        totalCompletedTrips: Int = 0,
        totalGamesPlayed: Int = 0,
        totalDiscoveries: Int = 0,
        totalWeightedScore: Double = 0,
        familyOnlyTripsCount: Int = 0,
        lastComputedAt: Date = .now
    ) {
        self.userId = userId
        self.totalCompletedTrips = totalCompletedTrips
        self.totalGamesPlayed = totalGamesPlayed
        self.totalDiscoveries = totalDiscoveries
        self.totalWeightedScore = totalWeightedScore
        self.familyOnlyTripsCount = familyOnlyTripsCount
        self.lastComputedAt = lastComputedAt
    }
}
