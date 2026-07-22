//
//  UserLifetimeStatsRepository.swift
//  LicensePlateApp
//
//  Fetch / upsert for cached lifetime stats row only.
//

import Foundation
import SwiftData

enum UserLifetimeStatsRepositoryError: Error, LocalizedError {
    case noModelContext
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "error.lifetime_stats_no_context".localized
        case .saveFailed(let e): return e.localizedDescription
        }
    }
}

@MainActor
final class UserLifetimeStatsRepository {
    static let shared = UserLifetimeStatsRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func fetch(forUserId userId: String) throws -> UserLifetimeStats? {
        guard let ctx = modelContext else { throw UserLifetimeStatsRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<UserLifetimeStatsEntity>(
            predicate: #Predicate<UserLifetimeStatsEntity> { $0.userId == userId }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return nil }
        return UserLifetimeStats(
            totalCompletedTrips: entity.totalCompletedTrips,
            totalGamesPlayed: entity.totalGamesPlayed,
            totalDiscoveries: entity.totalDiscoveries,
            totalWeightedScore: entity.totalWeightedScore,
            familyOnlyTripsCount: entity.familyOnlyTripsCount,
            friendsOnlyTripsCount: entity.friendsOnlyTripsCount,
            mixedFriendsFamilyTripsCount: entity.mixedFriendsFamilyTripsCount,
            entireFamilyTripsCount: entity.entireFamilyTripsCount,
            lastComputedAt: entity.lastComputedAt
        )
    }

    func upsert(userId: String, stats: UserLifetimeStats) throws {
        guard let ctx = modelContext else { throw UserLifetimeStatsRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<UserLifetimeStatsEntity>(
            predicate: #Predicate<UserLifetimeStatsEntity> { $0.userId == userId }
        )
        let entity: UserLifetimeStatsEntity
        if let existing = try ctx.fetch(descriptor).first {
            entity = existing
        } else {
            entity = UserLifetimeStatsEntity(userId: userId)
            ctx.insert(entity)
        }
        entity.totalCompletedTrips = stats.totalCompletedTrips
        entity.totalGamesPlayed = stats.totalGamesPlayed
        entity.totalDiscoveries = stats.totalDiscoveries
        entity.totalWeightedScore = stats.totalWeightedScore
        entity.familyOnlyTripsCount = stats.familyOnlyTripsCount
        entity.friendsOnlyTripsCount = stats.friendsOnlyTripsCount
        entity.mixedFriendsFamilyTripsCount = stats.mixedFriendsFamilyTripsCount
        entity.entireFamilyTripsCount = stats.entireFamilyTripsCount
        entity.lastComputedAt = stats.lastComputedAt
        do {
            try ctx.save()
        } catch {
            throw UserLifetimeStatsRepositoryError.saveFailed(underlying: error)
        }
    }

    /// Hard sign-out: delete all cached lifetime stats rows.
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw UserLifetimeStatsRepositoryError.noModelContext }
        try ctx.delete(model: UserLifetimeStatsEntity.self)
        try ctx.save()
    }
}
