//
//  AchievementProgressResolverTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AchievementProgressResolverTests {

    private let catalog = ProgressionCatalog.bundledDefault

    private func entry(id: String) -> ProgressionCatalogAchievement {
        guard let achievement = catalog.achievements.first(where: { $0.id == id }) else {
            Issue.record("Missing achievement \(id)")
            return catalog.achievements[0]
        }
        return achievement
    }

    private func status(id: String, inputs: AchievementProgressInputs) -> AchievementStatus {
        AchievementProgressResolver.statuses(for: [entry(id: id)], inputs: inputs)[id] ?? .locked
    }

    @Test func firstWinUnlocksFromEverCompetitiveFirstPlace() {
        let inputs = AchievementProgressInputs(
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
        let result = status(id: "first_win", inputs: inputs)
        #expect(result.isUnlocked)
        #expect(result.progress == 1)
    }

    @Test func explorerProgressUsesAcceptedRegionCount() {
        let inputs = AchievementProgressInputs(
            progression: UserProgressionEffectiveTotals(
                totalXp: 0,
                acceptedRegionFindCount: 7,
                competitiveFirstPlaceFinishes: 0,
                everCompetitiveFirstPlace: false,
                hasPendingLocalProgression: false
            ),
            lifetimeStats: nil,
            isFamilyMember: false,
            isRoyale: false,
            isFounder: false
        )
        let result = status(id: "explorer_10", inputs: inputs)
        #expect(!result.isUnlocked)
        #expect(result.progress == 7)
    }

    @Test func plateSpotterUsesLifetimeDiscoveries() {
        let inputs = AchievementProgressInputs(
            progression: nil,
            lifetimeStats: UserLifetimeStats(
                totalCompletedTrips: 0,
                totalGamesPlayed: 0,
                totalDiscoveries: 150,
                totalWeightedScore: 0,
                familyOnlyTripsCount: 0,
                lastComputedAt: .now
            ),
            isFamilyMember: false,
            isRoyale: false,
            isFounder: false
        )
        let result = status(id: "plates_100", inputs: inputs)
        #expect(result.isUnlocked)
        #expect(result.progress == 150)
    }

    @Test func familyUnlocksFromMembershipFlag() {
        let inputs = AchievementProgressInputs(
            progression: nil,
            lifetimeStats: nil,
            isFamilyMember: true,
            isRoyale: false,
            isFounder: false
        )
        #expect(status(id: "family", inputs: inputs).isUnlocked)
    }

    @Test func royaleUnlocksFromEntitlementFlag() {
        let inputs = AchievementProgressInputs(
            progression: nil,
            lifetimeStats: nil,
            isFamilyMember: false,
            isRoyale: true,
            isFounder: false
        )
        #expect(status(id: "royale", inputs: inputs).isUnlocked)
    }

    @Test func deferredEvaluatorsStayLocked() {
        let inputs = AchievementProgressInputs(
            progression: UserProgressionEffectiveTotals(
                totalXp: 999_999,
                acceptedRegionFindCount: 63,
                competitiveFirstPlaceFinishes: 200,
                everCompetitiveFirstPlace: true,
                hasPendingLocalProgression: false
            ),
            lifetimeStats: UserLifetimeStats(
                totalCompletedTrips: 100,
                totalGamesPlayed: 500,
                totalDiscoveries: 5_000,
                totalWeightedScore: 0,
                familyOnlyTripsCount: 0,
                lastComputedAt: .now
            ),
            isFamilyMember: true,
            isRoyale: true,
            isFounder: true
        )
        #expect(!status(id: "streak_5", inputs: inputs).isUnlocked)
        #expect(!status(id: "flawless", inputs: inputs).isUnlocked)
    }
}
