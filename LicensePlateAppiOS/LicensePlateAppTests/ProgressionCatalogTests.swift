//
//  ProgressionCatalogTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionCatalogTests {

    @Test func fixtureDefaultEqualsBundledDefault() {
        #expect(ProgressionCatalog.fixtureDefault == ProgressionCatalog.bundledDefault)
    }

    @Test func bundledDefaultRoundTripsThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProgressionCatalog.bundledDefault)
        let decoded = try #require(ProgressionCatalogLoader.decode(data))
        #expect(decoded == ProgressionCatalog.bundledDefault)
    }

    @Test func loadBundledFromAppModuleBundle() {
        let bundle = Bundle(for: RemoteConfigService.self)
        let loaded = ProgressionCatalogLoader.loadBundled(bundle: bundle)
        #expect(loaded == ProgressionCatalog.bundledDefault)
    }

    @Test func bundledCatalogMatchesLegacySwiftFixtures() {
        let catalog = ProgressionCatalog.bundledDefault
        let legacyById = Dictionary(uniqueKeysWithValues: Achievement.catalog.map { ($0.id, $0) })

        #expect(catalog.achievements.count == legacyById.count)

        for entry in catalog.achievements {
            let legacy = try #require(legacyById[entry.id])
            #expect(entry.goal == legacy.goal)
            #expect(entry.xpReward == legacy.xpReward)
            #expect(entry.icon == legacy.icon)
            #expect(entry.rarity.rawValue == legacyRarity(legacy.rarity))
            #expect(entry.category.rawValue == legacyCategory(legacy.category))
        }

        let legacyThresholds = RankLadder.standard.ranks.map(\.xpRequired)
        let catalogThresholds = catalog.rankLadder.ranks.sorted(by: { $0.level < $1.level }).map(\.xpRequired)
        #expect(catalogThresholds == legacyThresholds)

        #expect(catalog.rankLadder.ranks.count == RankLadder.standard.ranks.count)
        for legacyRank in RankLadder.standard.ranks {
            let catalogRank = try #require(catalog.rankLadder.ranks.first { $0.level == legacyRank.level })
            #expect(catalogRank.xpRequired == legacyRank.xpRequired)
            #expect(catalogRank.unlocks.count == legacyRank.unlocks.count)
        }
    }

    @Test func deferredAchievementsAreHidden() {
        let catalog = ProgressionCatalog.bundledDefault
        let streak = try #require(catalog.achievements.first { $0.id == "streak_5" })
        let flawless = try #require(catalog.achievements.first { $0.id == "flawless" })
        #expect(streak.hidden)
        #expect(streak.evaluator == .winStreak)
        #expect(flawless.hidden)
        #expect(flawless.evaluator == .flawless)
    }

    @Test func visibleAchievementsExcludesHidden() {
        let catalog = ProgressionCatalog.bundledDefault
        let visibleIds = Set(catalog.visibleAchievements.map(\.id))
        #expect(!visibleIds.contains("streak_5"))
        #expect(!visibleIds.contains("flawless"))
        #expect(visibleIds.contains("first_win"))
        #expect(catalog.visibleAchievements.count == catalog.achievements.count - 2)
    }

    @Test func validatorRejectsUnsupportedSchemaVersion() {
        var catalog = ProgressionCatalog.bundledDefault
        catalog.schemaVersion = 99
        #expect(ProgressionCatalogValidator.validate(catalog) == .invalid(reason: "unsupported_schema_version"))
    }

    @Test func validatorRejectsDuplicateAchievementIds() {
        var catalog = ProgressionCatalog.bundledDefault
        catalog.achievements.append(catalog.achievements[0])
        #expect(ProgressionCatalogValidator.validate(catalog) == .invalid(reason: "achievement_duplicate_id"))
    }

    @Test func validatorRejectsInvalidGoal() {
        var catalog = ProgressionCatalog.bundledDefault
        catalog.achievements[0].goal = 0
        #expect(ProgressionCatalogValidator.validate(catalog) == .invalid(reason: "achievement_goal_out_of_range"))
    }

    @Test func validatorRejectsOversizedXpReward() {
        var catalog = ProgressionCatalog.bundledDefault
        catalog.achievements[0].xpReward = 10_001
        #expect(ProgressionCatalogValidator.validate(catalog) == .invalid(reason: "achievement_xpReward_out_of_range"))
    }

    @Test func validatorRejectsDeferredEvaluatorWhenVisible() {
        var catalog = ProgressionCatalog.bundledDefault
        if let index = catalog.achievements.firstIndex(where: { $0.id == "streak_5" }) {
            catalog.achievements[index].hidden = false
        }
        #expect(
            ProgressionCatalogValidator.validate(catalog)
                == .invalid(reason: "achievement_deferred_evaluator_must_be_hidden")
        )
    }

    @Test func validatorRejectsNonMonotonicRankThresholds() {
        var catalog = ProgressionCatalog.bundledDefault
        if let index = catalog.rankLadder.ranks.firstIndex(where: { $0.level == 4 }) {
            catalog.rankLadder.ranks[index].xpRequired = 500
        }
        #expect(ProgressionCatalogValidator.validate(catalog) == .invalid(reason: "rank_xpRequired_not_monotonic"))
    }

    @Test func mergeUpdatesPresentationOnly() {
        let overrideJSON = """
        {"achievementsEnabled":false,"rankProgressionEnabled":true}
        """
        let merged = ProgressionCatalogLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: overrideJSON
        )
        #expect(merged.achievements == ProgressionCatalog.bundledDefault.achievements)
        #expect(merged.rankLadder == ProgressionCatalog.bundledDefault.rankLadder)
        #expect(merged.presentation.achievementsEnabled == false)
        #expect(merged.presentation.rankProgressionEnabled == true)
    }

    @Test func mergeIgnoresInvalidPresentationOverride() {
        let merged = ProgressionCatalogLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: "{ not json }"
        )
        #expect(merged == ProgressionCatalog.bundledDefault)
    }

    @Test func mergeIgnoresEmptyOverride() {
        let merged = ProgressionCatalogLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: "   "
        )
        #expect(merged == ProgressionCatalog.bundledDefault)
    }

    @Test func decodeRejectsInvalidJSON() {
        let data = Data("{ not json }".utf8)
        #expect(ProgressionCatalogLoader.decode(data) == nil)
    }

    // MARK: - Legacy mapping helpers

    private func legacyRarity(_ rarity: LicenseRarity) -> String {
        switch rarity {
        case .common: return "common"
        case .rare: return "rare"
        case .epic: return "epic"
        case .legendary: return "legendary"
        case .mythic: return "mythic"
        }
    }

    private func legacyCategory(_ category: AchievementCategory) -> String {
        switch category {
        case .exploration: return "exploration"
        case .collection: return "collection"
        case .competition: return "competition"
        case .milestones: return "milestones"
        case .social: return "social"
        }
    }
}
