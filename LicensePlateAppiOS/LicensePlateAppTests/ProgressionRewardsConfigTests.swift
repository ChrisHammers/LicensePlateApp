//
//  ProgressionRewardsConfigTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionRewardsConfigTests {

    @Test func bundledDefaultMatchesGameProgressionXPRewards() {
        let xp = ProgressionRewardsConfig.bundledDefault.xp
        #expect(xp.baseDiscoveryXp == GameProgressionXPRewards.baseDiscoveryXp)
        #expect(xp.firstFinderBonusXp == GameProgressionXPRewards.firstFinderBonusXp)
        #expect(xp.firstPlateFindBonusXp == GameProgressionXPRewards.firstPlateFindBonusXp)
        #expect(xp.baseMultiplayerGameBonusXp == GameProgressionXPRewards.baseMultiplayerGameBonusXp)
        #expect(xp.competitiveFirstPlaceFinishBonusXp == GameProgressionXPRewards.competitiveFirstPlaceFinishBonusXp)
        #expect(xp.competitiveSecondPlaceFinishBonusXp == GameProgressionXPRewards.competitiveSecondPlaceFinishBonusXp)
        #expect(xp.competitiveThirdPlaceFinishBonusXp == GameProgressionXPRewards.competitiveThirdPlaceFinishBonusXp)
        #expect(xp.gameContributorBonusXp == GameProgressionXPRewards.gameContributorBonusXp)
        #expect(xp.tripContributorBonusXp == GameProgressionXPRewards.tripContributorBonusXp)
        #expect(xp.firstTripCompletionBonusXp == GameProgressionXPRewards.firstTripCompletionBonusXp)
        #expect(xp.firstMultiplayerTripCompletionBonusXp == GameProgressionXPRewards.firstMuliplayerTripCompletionBonusXp)
        #expect(xp.firstGameCompletionBonusXp == GameProgressionXPRewards.firstGameCompletionBonusXp)
        #expect(xp.firstMultiplayerGameCompletionBonusXp == GameProgressionXPRewards.firstMulitplayerGameCompletionBonusXp)
        #expect(xp.baseMilestoneBonusXp == GameProgressionXPRewards.baseMilestoneBonusXp)
        #expect(ProgressionRewardsConfig.bundledDefault.policy.minimumLocalReconciliationDelta
            == GameProgressionXPRewards.minimumLocalReconciliationDelta)
    }

    @Test func fixtureDefaultEqualsBundledDefault() {
        #expect(ProgressionRewardsConfig.fixtureDefault == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func bundledDefaultRoundTripsThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProgressionRewardsConfig.bundledDefault)
        let decoded = try #require(ProgressionRewardsConfigLoader.decode(data))
        #expect(decoded == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func loadBundledFromAppModuleBundle() {
        let bundle = Bundle(for: RemoteConfigService.self)
        let loaded = ProgressionRewardsConfigLoader.loadBundled(bundle: bundle)
        #expect(loaded == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func validatorRejectsUnsupportedSchemaVersion() {
        var config = ProgressionRewardsConfig.bundledDefault
        config.schemaVersion = 99
        #expect(ProgressionRewardsConfigValidator.validate(config) == .invalid(reason: "unsupported_schema_version"))
    }

    @Test func validatorRejectsNegativeXp() {
        var config = ProgressionRewardsConfig.bundledDefault
        config.xp.baseDiscoveryXp = -1
        #expect(ProgressionRewardsConfigValidator.validate(config) == .invalid(reason: "xp_baseDiscoveryXp_out_of_range"))
    }

    @Test func validatorRejectsOversizedXp() {
        var config = ProgressionRewardsConfig.bundledDefault
        config.xp.baseDiscoveryXp = 1_001
        #expect(ProgressionRewardsConfigValidator.validate(config) == .invalid(reason: "xp_baseDiscoveryXp_out_of_range"))
    }

    @Test func validatorRejectsPresentationOutOfRange() {
        var config = ProgressionRewardsConfig.bundledDefault
        config.presentation.visualBandSize = 5
        #expect(
            ProgressionRewardsConfigValidator.validate(config)
                == .invalid(reason: "presentation_visualBandSize_out_of_range")
        )
    }

    @Test func mergeUpdatesPresentationOnly() {
        let overrideJSON = """
        {"visualBandSize":200,"xpPerRankLevel":5000}
        """
        let merged = ProgressionRewardsConfigLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: overrideJSON
        )
        #expect(merged.xp == ProgressionRewardsConfig.bundledDefault.xp)
        #expect(merged.policy == ProgressionRewardsConfig.bundledDefault.policy)
        #expect(merged.presentation.visualBandSize == 200)
        #expect(merged.presentation.xpPerRankLevel == 5_000)
    }

    @Test func mergeIgnoresInvalidPresentationOverride() {
        let merged = ProgressionRewardsConfigLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: "{\"visualBandSize\":1}"
        )
        #expect(merged == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func mergeIgnoresEmptyOverride() {
        let merged = ProgressionRewardsConfigLoader.merge(
            bundled: .bundledDefault,
            presentationOverrideJSON: "   "
        )
        #expect(merged == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func decodeRejectsInvalidJSON() {
        let data = Data("{ not json }".utf8)
        #expect(ProgressionRewardsConfigLoader.decode(data) == nil)
    }
}
