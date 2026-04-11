//
//  UserProgressionMilestoneDetectorTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct UserProgressionMilestoneDetectorTests {

    @Test func milestoneWhenEverFirstPlaceFlips() {
        let prev = UserProgressionSnapshot(
            totalXp: 10,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil
        )
        let next = UserProgressionSnapshot(
            totalXp: 60,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 1,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil
        )
        let keys = UserProgressionMilestoneDetector.milestoneKeys(previous: prev, next: next)
        #expect(keys.contains("ever_competitive_first_place"))
    }

    @Test func noMilestoneWhenAlreadyTrue() {
        let prev = UserProgressionSnapshot(
            totalXp: 60,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 1,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil
        )
        let next = UserProgressionSnapshot(
            totalXp: 110,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 2,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil
        )
        let keys = UserProgressionMilestoneDetector.milestoneKeys(previous: prev, next: next)
        #expect(keys.isEmpty)
    }

    @Test func firstSnapshotMilestoneWhenDocAlreadyTrue() {
        let next = UserProgressionSnapshot(
            totalXp: 60,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 1,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil
        )
        let keys = UserProgressionMilestoneDetector.milestoneKeys(previous: nil, next: next)
        #expect(keys.contains("ever_competitive_first_place"))
    }

    @Test func xpDeltaNonNegative() {
        let prev = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil
        )
        let next = UserProgressionSnapshot(
            totalXp: 80,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil
        )
        #expect(UserProgressionMilestoneDetector.totalXpDelta(previous: prev, next: next) == 0)
    }
}
