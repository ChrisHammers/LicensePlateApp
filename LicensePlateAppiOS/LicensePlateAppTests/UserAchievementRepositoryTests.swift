//
//  UserAchievementRepositoryTests.swift
//  LicensePlateAppTests
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct UserAchievementRepositoryTests {

    private func makeRepository() throws -> UserAchievementRepository {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        let repo = UserAchievementRepository()
        repo.setModelContext(ModelContext(container))
        return repo
    }

    @Test func backfillIfMissingInsertsOnce() throws {
        let repo = try makeRepository()
        #expect(try repo.backfillIfMissing(userId: "u1", achievementId: "first_win", lastProgress: 1))
        #expect(try !repo.backfillIfMissing(userId: "u1", achievementId: "first_win", lastProgress: 1))
        let records = try repo.fetchRecords(forUserId: "u1")
        #expect(records["first_win"]?.isBackfilled == true)
        #expect(records["first_win"]?.lastProgress == 1)
    }

    @Test func recordUnlockReplacesBackfilledRowWithKnownDate() throws {
        let repo = try makeRepository()
        _ = try repo.backfillIfMissing(userId: "u1", achievementId: "trips_10", lastProgress: 10)
        let unlockDate = Date(timeIntervalSince1970: 1_700_000_000)
        try repo.recordUnlock(userId: "u1", achievementId: "trips_10", unlockedAt: unlockDate, lastProgress: 10)
        let record = try #require(try repo.fetchRecords(forUserId: "u1")["trips_10"])
        #expect(record.isBackfilled == false)
        #expect(record.unlockedAt == unlockDate)
    }

    @Test func fetchRecordIdsReturnsAchievementKeys() throws {
        let repo = try makeRepository()
        _ = try repo.backfillIfMissing(userId: "u1", achievementId: "family", lastProgress: 1)
        let ids = try repo.fetchRecordIds(forUserId: "u1")
        #expect(ids == ["family"])
    }
}

struct AchievementProgressPersistenceTests {

    @Test func applyPersistedRecordsSetsKnownUnlockDate() {
        let computed: [String: AchievementStatus] = [
            "first_win": AchievementStatus(isUnlocked: true, progress: 1)
        ]
        let persisted: [String: UserAchievementRecord] = [
            "first_win": UserAchievementRecord(
                userId: "u1",
                achievementId: "first_win",
                unlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastProgress: 1,
                isBackfilled: false
            )
        ]
        let merged = AchievementProgressPersistence.applyPersistedRecords(
            statuses: computed,
            persisted: persisted
        )
        #expect(merged["first_win"]?.unlockedDate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func applyPersistedRecordsSkipsDateForBackfilledRows() {
        let computed: [String: AchievementStatus] = [
            "trips_10": AchievementStatus(isUnlocked: true, progress: 10)
        ]
        let persisted: [String: UserAchievementRecord] = [
            "trips_10": UserAchievementRecord(
                userId: "u1",
                achievementId: "trips_10",
                unlockedAt: .now,
                lastProgress: 10,
                isBackfilled: true
            )
        ]
        let merged = AchievementProgressPersistence.applyPersistedRecords(
            statuses: computed,
            persisted: persisted
        )
        #expect(merged["trips_10"]?.unlockedDate == nil)
    }

    @Test func filterNotYetPersistedExcludesStoredIds() {
        let ids = ["first_win", "trips_10", "family"]
        let filtered = AchievementProgressPersistence.filterNotYetPersisted(ids, persistedIds: ["trips_10"])
        #expect(filtered == ["first_win", "family"])
    }
}
