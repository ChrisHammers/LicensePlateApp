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
    var friendsOnlyTripsCount: Int
    var mixedFriendsFamilyTripsCount: Int
    var entireFamilyTripsCount: Int
    var lastComputedAt: Date

    init(
        totalCompletedTrips: Int,
        totalGamesPlayed: Int,
        totalDiscoveries: Int,
        totalWeightedScore: Double,
        familyOnlyTripsCount: Int,
        friendsOnlyTripsCount: Int = 0,
        mixedFriendsFamilyTripsCount: Int = 0,
        entireFamilyTripsCount: Int = 0,
        lastComputedAt: Date
    ) {
        self.totalCompletedTrips = totalCompletedTrips
        self.totalGamesPlayed = totalGamesPlayed
        self.totalDiscoveries = totalDiscoveries
        self.totalWeightedScore = totalWeightedScore
        self.familyOnlyTripsCount = familyOnlyTripsCount
        self.friendsOnlyTripsCount = friendsOnlyTripsCount
        self.mixedFriendsFamilyTripsCount = mixedFriendsFamilyTripsCount
        self.entireFamilyTripsCount = entireFamilyTripsCount
        self.lastComputedAt = lastComputedAt
    }
}
