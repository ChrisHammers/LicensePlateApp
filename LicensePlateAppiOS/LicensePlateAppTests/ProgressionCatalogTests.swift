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

    @Test func bundledCatalogMatchesShippedParityFixtures() throws {
        let catalog = ProgressionCatalog.bundledDefault
        #expect(catalog.achievements.count == ProgressionCatalogLegacyParity.achievementCount)
        #expect(catalog.visibleAchievements.count == ProgressionCatalogLegacyParity.visibleAchievementCount)

        for (id, expected) in ProgressionCatalogLegacyParity.achievementExpectations {
            let entry = try #require(catalog.achievements.first { $0.id == id })
            #expect(entry.goal == expected.goal)
            #expect(entry.xpReward == expected.xpReward)
            #expect(entry.icon == expected.icon)
            #expect(entry.rarity.rawValue == expected.rarity)
            #expect(entry.category.rawValue == expected.category)
        }

        let catalogThresholds = catalog.rankLadder.ranks.sorted(by: { $0.level < $1.level }).map(\.xpRequired)
        #expect(catalogThresholds == ProgressionCatalogLegacyParity.rankXpThresholds)
        #expect(catalog.rankLadder.ranks.count == ProgressionCatalogLegacyParity.rankCount)
    }

    @Test func deferredAchievementsAreHidden() throws {
        let catalog = ProgressionCatalog.bundledDefault
        let streak = try #require(catalog.achievements.first { $0.id == "streak_5" })
        let flawless = try #require(catalog.achievements.first { $0.id == "flawless" })
        #expect(streak.hidden)
        #expect(streak.evaluator == .winStreak)
        #expect(flawless.hidden)
        #expect(flawless.evaluator == .flawless)
    }

    @Test func returnStreakToastGroupRequiresMinStreakTwo() throws {
        let group = try #require(ProgressionCatalog.bundledDefault.xpToastGroup(id: "return_streak"))
        #expect(group.xpReward == 15)
        #expect(group.minStreakForXpReward == 2)
    }

    @Test func validatorRejectsInvalidMinStreakForXpReward() {
        var catalog = ProgressionCatalog.bundledDefault
        if let index = catalog.xpToast.groups.firstIndex(where: { $0.id == "return_streak" }) {
            catalog.xpToast.groups[index].minStreakForXpReward = 0
        }
        #expect(
            ProgressionCatalogValidator.validate(catalog)
                == .invalid(reason: "xp_toast_group_min_streak_for_xp_reward_out_of_range")
        )
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

    @Test func providerReturnsBundledCatalog() {
        let provider = ProgressionCatalogProvider()
        #expect(provider.current == ProgressionCatalog.bundledDefault)
    }

    @Test func providerRefreshIsIdempotentWithoutOverride() {
        let provider = ProgressionCatalogProvider()
        let before = provider.current
        provider.refresh(presentationOverrideJSON: nil)
        #expect(provider.current == before)
    }

    @Test func providerRefreshAppliesValidPresentationOverride() {
        let provider = ProgressionCatalogProvider()
        provider.refresh(presentationOverrideJSON: """
        {"achievementsEnabled":false,"rankProgressionEnabled":true}
        """)
        #expect(provider.current.presentation.achievementsEnabled == false)
        #expect(provider.current.presentation.rankProgressionEnabled == true)
        #expect(provider.current.achievements == ProgressionCatalog.bundledDefault.achievements)
        #expect(provider.current.rankLadder == ProgressionCatalog.bundledDefault.rankLadder)
    }

    @Test func providerRefreshIgnoresInvalidPresentationOverride() {
        let provider = ProgressionCatalogProvider()
        provider.refresh(presentationOverrideJSON: "{ not json }")
        #expect(provider.current.presentation == ProgressionCatalog.bundledDefault.presentation)
    }

    @Test func mergeUpdatesXpToastOnly() {
        let overrideJSON = """
        {"burstDurationSeconds":6,"groups":[{"id":"discovery","displayOrder":10,"titleKeySingle":"custom.single","titleKeyMulti":"custom.multi","matchers":{"ledgerGrantKinds":["final_discovery_award"]}}]}
        """
        let merged = ProgressionCatalogLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: nil,
            xpToastOverrideJSON: overrideJSON
        )
        #expect(merged.xpToast.burstDurationSeconds == 6)
        #expect(merged.xpToast.groups.count == 1)
        #expect(merged.achievements == ProgressionCatalog.bundledDefault.achievements)
    }

    @Test func mergeIgnoresInvalidXpToastOverride() {
        let merged = ProgressionCatalogLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: nil,
            xpToastOverrideJSON: "{ not json }"
        )
        #expect(merged.xpToast == ProgressionCatalog.bundledDefault.xpToast)
    }

    @Test func validatorRejectsInvalidXpToastBurstDuration() {
        var xpToast = ProgressionCatalog.bundledDefault.xpToast
        xpToast.burstDurationSeconds = 0
        #expect(ProgressionCatalogValidator.validateXpToastOverride(xpToast) == .invalid(reason: "xp_toast_burst_duration_out_of_range"))
    }
}
