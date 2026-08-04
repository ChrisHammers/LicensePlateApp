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

    @Test func providerReturnsBundledConfig() {
        let provider = ProgressionRewardsConfigProvider()
        #expect(provider.current == ProgressionRewardsConfig.bundledDefault)
    }

    @Test func providerRefreshIsIdempotentWithoutOverride() {
        let provider = ProgressionRewardsConfigProvider()
        let before = provider.current
        provider.refresh(presentationOverrideJSON: nil)
        #expect(provider.current == before)
    }

    @Test func providerRefreshAppliesValidPresentationOverride() {
        let provider = ProgressionRewardsConfigProvider()
        provider.refresh(presentationOverrideJSON: """
        {"visualBandSize":200,"xpPerRankLevel":5000}
        """)
        #expect(provider.current.presentation.visualBandSize == 200)
        #expect(provider.current.presentation.xpPerRankLevel == 5_000)
        #expect(provider.current.xp == ProgressionRewardsConfig.bundledDefault.xp)
    }

    @Test func providerRefreshIgnoresInvalidPresentationOverride() {
        let provider = ProgressionRewardsConfigProvider()
        provider.refresh(presentationOverrideJSON: "{\"visualBandSize\":1}")
        #expect(provider.current.presentation == ProgressionRewardsConfig.bundledDefault.presentation)
    }

    @Test func rankBandsRespectPresentationOverride() {
        let presentation = ProgressionPresentationRewards(visualBandSize: 200, xpPerRankLevel: 5_000)
        #expect(ProgressionRankBands.progressInCurrentBand(totalXp: 150, presentation: presentation) == 0.75)
        #expect(ProgressionRankBands.pendingOverlayFraction(pendingXp: 100, presentation: presentation) == 0.5)
    }

    @Test func projectedBandFillFitsInCurrentBand() {
        let presentation = ProgressionPresentationRewards(visualBandSize: 100, xpPerRankLevel: 3_000)
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 37,
            pendingXp: 10,
            presentation: presentation
        )
        #expect(fill.syncedFractionInCurrentBand == 0.37)
        #expect(fill.pendingFractionInCurrentBand == 0.10)
        #expect(fill.pendingFractionInNextBand == 0)
        #expect(fill.pendingXpBeyondNextBand == 0)
        #expect(!fill.showsNextBandBar)
    }

    @Test func projectedBandFillSpillsIntoNextBandOnly() {
        let presentation = ProgressionPresentationRewards(visualBandSize: 100, xpPerRankLevel: 3_000)
        // room at 80 = 20; pending 50 → 20 current + 30 next + 0 beyond
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 80,
            pendingXp: 50,
            presentation: presentation
        )
        #expect(fill.syncedFractionInCurrentBand == 0.80)
        #expect(fill.pendingFractionInCurrentBand == 0.20)
        #expect(fill.pendingFractionInNextBand == 0.30)
        #expect(fill.pendingXpBeyondNextBand == 0)
        #expect(fill.showsNextBandBar)
        #expect(!fill.showsBeyondNextBandCaption)
    }

    @Test func projectedBandFillGoesPastNextBand() {
        let presentation = ProgressionPresentationRewards(visualBandSize: 100, xpPerRankLevel: 3_000)
        // Screenshot-like: 320 → 20 in band, room 80; +390 → 80 current, 100 next, 210 beyond
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 320,
            pendingXp: 390,
            presentation: presentation
        )
        #expect(fill.syncedFractionInCurrentBand == 0.20)
        #expect(fill.pendingFractionInCurrentBand == 0.80)
        #expect(fill.pendingFractionInNextBand == 1.0)
        #expect(fill.pendingXpBeyondNextBand == 210)
        #expect(fill.showsNextBandBar)
        #expect(fill.showsBeyondNextBandCaption)
    }

    @Test func roomInCurrentBandAtBoundaryIsFullBand() {
        let presentation = ProgressionPresentationRewards(visualBandSize: 100, xpPerRankLevel: 3_000)
        #expect(ProgressionRankBands.roomInCurrentBand(serverXp: 300, presentation: presentation) == 100)
        #expect(ProgressionRankBands.roomInCurrentBand(serverXp: 320, presentation: presentation) == 80)
    }

    @Test func rankLadderFromCatalogAtTenThousandXp() {
        let ladder = ProgressionCatalogProjection.rankLadder(from: .bundledDefault)
        #expect(ladder.currentRank(xp: 10_000).level == 4)
    }
}
