//
//  AchievementEvaluatorParityTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AchievementEvaluatorParityTests {

    private struct FixtureFile: Decodable {
        var cases: [FixtureCase]
    }

    private struct FixtureCase: Decodable {
        var achievementId: String
        var inputs: FixtureInputs
        var expected: FixtureExpected
    }

    private struct FixtureInputs: Decodable {
        var progression: FixtureProgression?
        var lifetimeStats: FixtureLifetimeStats?
        var isFamilyMember: Bool
        var isRoyale: Bool
        var isFounder: Bool
    }

    private struct FixtureProgression: Decodable {
        var everCompetitiveFirstPlace: Bool?
        var acceptedRegionFindCount: Int?
        var competitiveFirstPlaceFinishes: Int?
    }

    private struct FixtureLifetimeStats: Decodable {
        var totalCompletedTrips: Int?
        var totalDiscoveries: Int?
    }

    private struct FixtureExpected: Decodable {
        var progress: Int
        var unlocked: Bool
    }

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AchievementEvaluatorParityFixtures.json")

    private static let fixture: FixtureFile = {
        let data = try! Data(contentsOf: fixtureURL)
        return try! JSONDecoder().decode(FixtureFile.self, from: data)
    }()

    private func entry(id: String) -> ProgressionCatalogAchievement {
        guard let achievement = ProgressionCatalog.bundledDefault.achievements.first(where: { $0.id == id }) else {
            Issue.record("Missing achievement \(id)")
            return ProgressionCatalog.bundledDefault.achievements[0]
        }
        return achievement
    }

    private func inputs(from fixture: FixtureInputs) -> AchievementProgressInputs {
        let progression: UserProgressionEffectiveTotals?
        if let p = fixture.progression {
            progression = UserProgressionEffectiveTotals(
                totalXp: 0,
                acceptedRegionFindCount: p.acceptedRegionFindCount ?? 0,
                competitiveFirstPlaceFinishes: p.competitiveFirstPlaceFinishes ?? 0,
                everCompetitiveFirstPlace: p.everCompetitiveFirstPlace ?? false,
                hasPendingLocalProgression: false
            )
        } else {
            progression = nil
        }

        let lifetimeStats: UserLifetimeStats?
        if let stats = fixture.lifetimeStats {
            lifetimeStats = UserLifetimeStats(
                totalCompletedTrips: stats.totalCompletedTrips ?? 0,
                totalGamesPlayed: 0,
                totalDiscoveries: stats.totalDiscoveries ?? 0,
                totalWeightedScore: 0,
                familyOnlyTripsCount: 0,
                lastComputedAt: .now
            )
        } else {
            lifetimeStats = nil
        }

        return AchievementProgressInputs(
            progression: progression,
            lifetimeStats: lifetimeStats,
            isFamilyMember: fixture.isFamilyMember,
            isRoyale: fixture.isRoyale,
            isFounder: fixture.isFounder
        )
    }

    @Test func allFixtureCasesMatchResolver() {
        for testCase in Self.fixture.cases {
            let achievement = entry(id: testCase.achievementId)
            #expect(!achievement.hidden)
            let result = AchievementProgressResolver.statuses(
                for: [achievement],
                inputs: inputs(from: testCase.inputs)
            )[testCase.achievementId] ?? .locked
            #expect(result.progress == testCase.expected.progress)
            #expect(result.isUnlocked == testCase.expected.unlocked)
        }
    }

    @Test func coversAllVisibleAchievementIds() {
        let covered = Set(Self.fixture.cases.map(\.achievementId))
        let visibleIds = ProgressionCatalog.bundledDefault.visibleAchievements.map(\.id)
        for id in visibleIds {
            #expect(covered.contains(id))
        }
    }
}
