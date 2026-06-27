//
//  UserAchievementRepository.swift
//  LicensePlateApp
//
//  Fetch / upsert for local achievement unlock rows.
//

import Foundation
import SwiftData
import Combine

enum UserAchievementRepositoryError: Error, LocalizedError {
    case noModelContext
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noModelContext: return "error.user_achievement_no_context".localized
        case .saveFailed(let e): return e.localizedDescription
        }
    }
}

@MainActor
final class UserAchievementRepository: ObservableObject {
    static let shared = UserAchievementRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func fetchRecords(forUserId userId: String) throws -> [String: UserAchievementRecord] {
        guard let ctx = modelContext else { throw UserAchievementRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.userId == userId }
        )
        let entities = try ctx.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: entities.map { entity in
            (entity.achievementId, map(entity))
        })
    }

    func fetchRecordIds(forUserId userId: String) throws -> Set<String> {
        Set(try fetchRecords(forUserId: userId).keys)
    }

    /// Records a live unlock (post-celebration). Overwrites backfilled rows with a known unlock time.
    func recordUnlock(
        userId: String,
        achievementId: String,
        unlockedAt: Date = .now,
        lastProgress: Int
    ) throws {
        try upsert(
            userId: userId,
            achievementId: achievementId,
            unlockedAt: unlockedAt,
            lastProgress: lastProgress,
            isBackfilled: false
        )
    }

    /// Inserts a row only when none exists (pre-existing unlock sync on baseline).
    @discardableResult
    func backfillIfMissing(
        userId: String,
        achievementId: String,
        lastProgress: Int
    ) throws -> Bool {
        guard let ctx = modelContext else { throw UserAchievementRepositoryError.noModelContext }
        let key = UserAchievementEntity.makeRecordKey(userId: userId, achievementId: achievementId)
        let descriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.recordKey == key }
        )
        if try ctx.fetch(descriptor).first != nil {
            return false
        }
        let entity = UserAchievementEntity(
            userId: userId,
            achievementId: achievementId,
            unlockedAt: .now,
            lastProgress: lastProgress,
            isBackfilled: true
        )
        ctx.insert(entity)
        do {
            try ctx.save()
            objectWillChange.send()
        } catch {
            throw UserAchievementRepositoryError.saveFailed(underlying: error)
        }
        return true
    }

    func updateProgressIfUnlocked(
        userId: String,
        achievementId: String,
        lastProgress: Int
    ) throws {
        guard let ctx = modelContext else { throw UserAchievementRepositoryError.noModelContext }
        let key = UserAchievementEntity.makeRecordKey(userId: userId, achievementId: achievementId)
        let descriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.recordKey == key }
        )
        guard let entity = try ctx.fetch(descriptor).first else { return }
        entity.lastProgress = max(entity.lastProgress, lastProgress)
        do {
            try ctx.save()
            objectWillChange.send()
        } catch {
            throw UserAchievementRepositoryError.saveFailed(underlying: error)
        }
    }

    private func upsert(
        userId: String,
        achievementId: String,
        unlockedAt: Date,
        lastProgress: Int,
        isBackfilled: Bool
    ) throws {
        guard let ctx = modelContext else { throw UserAchievementRepositoryError.noModelContext }
        let key = UserAchievementEntity.makeRecordKey(userId: userId, achievementId: achievementId)
        let descriptor = FetchDescriptor<UserAchievementEntity>(
            predicate: #Predicate<UserAchievementEntity> { $0.recordKey == key }
        )
        let entity: UserAchievementEntity
        if let existing = try ctx.fetch(descriptor).first {
            entity = existing
        } else {
            entity = UserAchievementEntity(
                userId: userId,
                achievementId: achievementId,
                unlockedAt: unlockedAt,
                lastProgress: lastProgress,
                isBackfilled: isBackfilled
            )
            ctx.insert(entity)
        }
        entity.unlockedAt = unlockedAt
        entity.lastProgress = max(entity.lastProgress, lastProgress)
        entity.isBackfilled = isBackfilled
        do {
            try ctx.save()
            objectWillChange.send()
        } catch {
            throw UserAchievementRepositoryError.saveFailed(underlying: error)
        }
    }

    private func map(_ entity: UserAchievementEntity) -> UserAchievementRecord {
        UserAchievementRecord(
            userId: entity.userId,
            achievementId: entity.achievementId,
            unlockedAt: entity.unlockedAt,
            lastProgress: entity.lastProgress,
            isBackfilled: entity.isBackfilled
        )
    }
}
