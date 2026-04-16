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
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        let next = UserProgressionSnapshot(
            totalXp: 60,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 1,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
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
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        let next = UserProgressionSnapshot(
            totalXp: 110,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 2,
            everCompetitiveFirstPlace: true,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
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
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        let keys = UserProgressionMilestoneDetector.milestoneKeys(previous: nil, next: next)
        #expect(keys.contains("ever_competitive_first_place"))
    }

    @Test func effectiveTotalsCombinedSetsPendingFlag() {
        let server = UserProgressionSnapshot(
            totalXp: 5,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        let pending = ProgressionPendingDelta(
            totalXp: 10,
            acceptedRegionFindCount: 1,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false
        )
        let eff = UserProgressionEffectiveTotals.combined(server: server, pending: pending)
        #expect(eff.totalXp == 15)
        #expect(eff.hasPendingLocalProgression)
    }

    @Test func xpDeltaNonNegative() {
        let prev = UserProgressionSnapshot(
            totalXp: 100,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        let next = UserProgressionSnapshot(
            totalXp: 80,
            acceptedRegionFindCount: 0,
            competitiveFirstPlaceFinishes: 0,
            everCompetitiveFirstPlace: false,
            lastUpdatedAt: nil,
            appliedProgressionEventIds: []
        )
        #expect(UserProgressionMilestoneDetector.totalXpDelta(previous: prev, next: next) == 0)
    }
}
