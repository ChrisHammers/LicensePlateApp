//
//  PublicLifetimeStatsCacheEntity.swift
//  LicensePlateApp
//
//  SwiftData cache for Firestore `public_lifetime_stats`.
//

import Foundation
import SwiftData

@Model
final class PublicLifetimeStatsCacheEntity {
    @Attribute(.unique) var userId: String
    var totalCompletedTrips: Int
    var totalGamesPlayed: Int
    var totalDiscoveries: Int
    var totalWeightedScore: Double
    var familyOnlyTripsCount: Int
    var friendsOnlyTripsCount: Int
    var mixedFriendsFamilyTripsCount: Int
    var entireFamilyTripsCount: Int
    /// Mirrors server `lastComputedAt` from the public aggregate document.
    var lastServerUpdatedAt: Date
    /// When this device last received a snapshot for this user.
    var lastFetchedAt: Date
    /// Family members are never LRU-evicted from the listener/cache policy.
    var isFamilyPinned: Bool
    /// LRU hint for friend rows (non-pinned).
    var lastAccessedAt: Date

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
        lastServerUpdatedAt: Date = .distantPast,
        lastFetchedAt: Date = .now,
        isFamilyPinned: Bool = false,
        lastAccessedAt: Date = .now
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
        self.lastServerUpdatedAt = lastServerUpdatedAt
        self.lastFetchedAt = lastFetchedAt
        self.isFamilyPinned = isFamilyPinned
        self.lastAccessedAt = lastAccessedAt
    }
}
