//
//  UserLifetimeStatsEntity.swift
//  LicensePlateApp
//
//  SwiftData cache row for profile lifetime stats.
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
    var friendsOnlyTripsCount: Int
    var mixedFriendsFamilyTripsCount: Int
    var entireFamilyTripsCount: Int
    var lastComputedAt: Date

    init(
        userId: String,
        totalCompletedTrips: Int = 0,
        totalGamesPlayed: Int = 0,
        totalDiscoveries: Int = 0,
        totalWeightedScore: Double = 0,
        familyOnlyTripsCount: Int = 0,
        friendsOnlyTripsCount: Int = 0,
        mixedFriendsFamilyTripsCount: Int = 0,
        entireFamilyTripsCount: Int = 0,
        lastComputedAt: Date = .now
    ) {
        self.userId = userId
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
