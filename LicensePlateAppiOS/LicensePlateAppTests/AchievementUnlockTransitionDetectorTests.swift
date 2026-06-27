//
//  AchievementUnlockTransitionDetectorTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AchievementUnlockTransitionDetectorTests {

    @Test func newlyUnlockedIds_emptyWhenNoPreviousSnapshot() {
        let next = ["a": AchievementStatus(isUnlocked: true, progress: 1)]
        let ids = AchievementUnlockTransitionDetector.newlyUnlockedAchievementIds(
            previous: nil,
            next: next
        )
        #expect(ids.isEmpty)
    }

    @Test func newlyUnlockedIds_detectsTransitionFromLockedToUnlocked() {
        let previous: [String: AchievementStatus] = [
            "first_win": .locked,
            "explorer_10": AchievementStatus(isUnlocked: true, progress: 10)
        ]
        let next: [String: AchievementStatus] = [
            "first_win": AchievementStatus(isUnlocked: true, progress: 1),
            "explorer_10": AchievementStatus(isUnlocked: true, progress: 10),
            "family": .locked
        ]
        let ids = AchievementUnlockTransitionDetector.newlyUnlockedAchievementIds(
            previous: previous,
            next: next
        )
        #expect(ids == ["first_win"])
    }

    @Test func newlyUnlockedIds_sortedAndDedupedByMap() {
        let previous = ["b": .locked, "a": .locked]
        let next = [
            "b": AchievementStatus(isUnlocked: true, progress: 1),
            "a": AchievementStatus(isUnlocked: true, progress: 1)
        ]
        let ids = AchievementUnlockTransitionDetector.newlyUnlockedAchievementIds(
            previous: previous,
            next: next
        )
        #expect(ids == ["a", "b"])
    }

    @Test func rankUpLevel_nilWhenNoPrevious() {
        #expect(AchievementUnlockTransitionDetector.rankUpLevel(previous: nil, nextLevel: 3) == nil)
    }

    @Test func rankUpLevel_nilWhenUnchangedOrDecreased() {
        #expect(AchievementUnlockTransitionDetector.rankUpLevel(previous: 3, nextLevel: 3) == nil)
        #expect(AchievementUnlockTransitionDetector.rankUpLevel(previous: 4, nextLevel: 3) == nil)
    }

    @Test func rankUpLevel_returnsNewLevelOnIncrease() {
        #expect(AchievementUnlockTransitionDetector.rankUpLevel(previous: 2, nextLevel: 3) == 3)
    }
}

struct AchievementProgressSnapshotTests {

    @Test func snapshot_equality() {
        let a = AchievementProgressSnapshot(
            statuses: ["x": AchievementStatus(isUnlocked: true, progress: 1)],
            rankLevel: 2,
            totalXp: 500
        )
        let b = AchievementProgressSnapshot(
            statuses: ["x": AchievementStatus(isUnlocked: true, progress: 1)],
            rankLevel: 2,
            totalXp: 500
        )
        #expect(a == b)
    }
}
