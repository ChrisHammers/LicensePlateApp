//
//  AchievementProgressSnapshotBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AchievementProgressSnapshotBuilderTests {

    private let user = AppUser(id: "u1", userName: "Tester", firebaseUID: "u1")
    private let catalogProvider = FixedProgressionCatalogProvider()

    private var firstWinInputs: AchievementProgressInputs {
        AchievementProgressInputs(
            progression: UserProgressionEffectiveTotals(
                totalXp: 100,
                acceptedRegionFindCount: 0,
                competitiveFirstPlaceFinishes: 1,
                everCompetitiveFirstPlace: true,
                hasPendingLocalProgression: false
            ),
            lifetimeStats: nil,
            isFamilyMember: false,
            isRoyale: false,
            isFounder: false
        )
    }

    @Test func emptyPersistenceUsesResolverOnlyStatuses() {
        let snapshot = AchievementProgressSnapshotBuilder.build(
            user: user,
            lifetimeStats: nil,
            totalXp: 100,
            catalogProvider: catalogProvider,
            inputs: firstWinInputs
        )
        #expect(snapshot.statuses["first_win"]?.isUnlocked == true)
        #expect(snapshot.statuses["first_win"]?.unlockedDate == nil)
    }

    @Test func localBackfillDoesNotSetUnlockedDate() {
        let local: [String: UserAchievementRecord] = [
            "first_win": UserAchievementRecord(
                userId: "u1",
                achievementId: "first_win",
                unlockedAt: Date(timeIntervalSince1970: 1_000),
                lastProgress: 1,
                isBackfilled: true,
                storedXpReward: nil
            )
        ]
        let snapshot = AchievementProgressSnapshotBuilder.build(
            user: user,
            lifetimeStats: nil,
            totalXp: 100,
            catalogProvider: catalogProvider,
            inputs: firstWinInputs,
            localPersistedRecords: local
        )
        #expect(snapshot.statuses["first_win"]?.isUnlocked == true)
        #expect(snapshot.statuses["first_win"]?.unlockedDate == nil)
    }

    @Test func remoteRecordOverridesLocalUnlockedDate() {
        let local: [String: UserAchievementRecord] = [
            "first_win": UserAchievementRecord(
                userId: "u1",
                achievementId: "first_win",
                unlockedAt: Date(timeIntervalSince1970: 1_000),
                lastProgress: 1,
                isBackfilled: true,
                storedXpReward: nil
            )
        ]
        let remoteDate = Date(timeIntervalSince1970: 1_700_000_000)
        let remote: [String: UserAchievementRecord] = [
            "first_win": UserAchievementRecord(
                userId: "u1",
                achievementId: "first_win",
                unlockedAt: remoteDate,
                lastProgress: 1,
                isBackfilled: false,
                storedXpReward: nil
            )
        ]
        let snapshot = AchievementProgressSnapshotBuilder.build(
            user: user,
            lifetimeStats: nil,
            totalXp: 100,
            catalogProvider: catalogProvider,
            inputs: firstWinInputs,
            localPersistedRecords: local,
            remotePersistedRecords: remote
        )
        #expect(snapshot.statuses["first_win"]?.unlockedDate == remoteDate)
    }

    @Test func remoteLoadedAfterLocalEmpty_preventsMissingPersistedIds() {
        let remote: [String: UserAchievementRecord] = [
            "first_win": UserAchievementRecord(
                userId: "u1",
                achievementId: "first_win",
                unlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastProgress: 1,
                isBackfilled: false,
                storedXpReward: nil
            )
        ]
        let persistedIds = AchievementProgressPersistence.persistedAchievementIds(
            local: [:],
            remote: remote
        )
        #expect(persistedIds.contains("first_win"))
        let filtered = AchievementProgressPersistence.filterNotYetPersisted(
            ["first_win"],
            persistedIds: persistedIds
        )
        #expect(filtered.isEmpty)
    }
}

private final class FixedProgressionCatalogProvider: ProgressionCatalogProviding, @unchecked Sendable {
    var current: ProgressionCatalog { .bundledDefault }
    func refresh(presentationOverrideJSON: String?) {}
}
