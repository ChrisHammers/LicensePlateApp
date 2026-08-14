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
        #expect(xp.lifetimeUniqueRegionFindBonusXp == GameProgressionXPRewards.lifetimeUniqueRegionFindBonusXp)
        #expect(xp.firstFindOfDayBonusXp == GameProgressionXPRewards.firstFindOfDayBonusXp)
        #expect(xp.competitiveFirstPlaceFinishBonusXp == GameProgressionXPRewards.competitiveFirstPlaceFinishBonusXp)
        #expect(xp.competitiveSecondPlaceFinishBonusXp == GameProgressionXPRewards.competitiveSecondPlaceFinishBonusXp)
        #expect(xp.competitiveThirdPlaceFinishBonusXp == GameProgressionXPRewards.competitiveThirdPlaceFinishBonusXp)
        #expect(xp.gameEndedBonusXp == GameProgressionXPRewards.gameEndedBonusXp)
        #expect(xp.gameFullClearBonusXp == GameProgressionXPRewards.gameFullClearBonusXp)
        #expect(xp.tripEndedBonusXp == GameProgressionXPRewards.tripEndedBonusXp)
        #expect(xp.tripParticipationBonusXp == GameProgressionXPRewards.tripParticipationBonusXp)
        #expect(xp.tripCompetitiveFirstPlaceBonusXp == GameProgressionXPRewards.tripCompetitiveFirstPlaceBonusXp)
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

    @Test func projectedBandFillMatchesToastEarlyRankFiftyXp() {
        let catalog = ProgressionCatalog.bundledDefault
        // Rank span 0→1000: 50 pending ≈ 5%
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 0,
            pendingXp: 50,
            catalog: catalog
        )
        #expect(fill.syncedFractionInCurrentBand == 0)
        #expect(abs(fill.pendingFractionInCurrentBand - 0.05) < 0.0001)
        #expect(fill.pendingFractionInNextBand == 0)
        #expect(fill.pendingXpBeyondNextBand == 0)
        #expect(!fill.showsNextBandBar)
        #expect(!fill.showsNextRankCaption)
        #expect(!fill.showsBeyondNextBandCaption)

        let toast = XpGainToastRankBandBuilder.build(
            totalXpBeforeBurst: 0,
            burstXpGained: 50,
            catalog: catalog
        )
        #expect(toast?.progressBeforeBurst == fill.syncedFractionInCurrentBand)
        #expect(
            abs((toast?.progressAfterBurst ?? -1) - (fill.syncedFractionInCurrentBand + fill.pendingFractionInCurrentBand))
                < 0.0001
        )
    }

    @Test func projectedBandFillMatchesToastCrossingOneRank() {
        let catalog = ProgressionCatalog.bundledDefault
        // 900 + 150 → after 1050 in 1000…3000 (toast segment-from-after)
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 900,
            pendingXp: 150,
            catalog: catalog
        )
        let toast = XpGainToastRankBandBuilder.build(
            totalXpBeforeBurst: 900,
            burstXpGained: 150,
            catalog: catalog
        )
        #expect(toast != nil)
        #expect(fill.syncedFractionInCurrentBand == toast?.progressBeforeBurst)
        #expect(
            abs(fill.pendingFractionInCurrentBand - ((toast?.progressAfterBurst ?? 0) - (toast?.progressBeforeBurst ?? 0)))
                < 0.0001
        )
        #expect(fill.pendingFractionInNextBand == 0)
        #expect(fill.pendingXpBeyondNextBand == 0)
        #expect(fill.showsNextRankCaption)
        #expect(!fill.showsBeyondNextBandCaption)
        #expect(!fill.showsNextBandBar)
    }

    @Test func projectedBandFillBeyondNextRank() {
        let catalog = ProgressionCatalog.bundledDefault
        // 0 + 3500 → past 3000 into third rank; beyond = 500
        let fill = ProgressionRankBands.projectedBandFill(
            serverXp: 0,
            pendingXp: 3500,
            catalog: catalog
        )
        let toast = XpGainToastRankBandBuilder.build(
            totalXpBeforeBurst: 0,
            burstXpGained: 3500,
            catalog: catalog
        )
        #expect(fill.syncedFractionInCurrentBand == toast?.progressBeforeBurst)
        #expect(
            abs(fill.pendingFractionInCurrentBand - ((toast?.progressAfterBurst ?? 0) - (toast?.progressBeforeBurst ?? 0)))
                < 0.0001
        )
        #expect(fill.pendingXpBeyondNextBand == 500)
        #expect(fill.showsBeyondNextBandCaption)
        #expect(!fill.showsNextRankCaption)
        #expect(!fill.showsNextBandBar)
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

    @Test func bundledAmountsMatchProductTable() {
        let xp = ProgressionRewardsConfig.bundledDefault.xp
        #expect(xp.baseDiscoveryXp == 10)
        #expect(xp.firstFinderBonusXp == 5)
        #expect(xp.lifetimeUniqueRegionFindBonusXp == 20)
        #expect(xp.firstFindOfDayBonusXp == 10)
        #expect(xp.competitiveFirstPlaceFinishBonusXp == 25)
        #expect(xp.competitiveSecondPlaceFinishBonusXp == 10)
        #expect(xp.competitiveThirdPlaceFinishBonusXp == 5)
        #expect(xp.gameEndedBonusXp == 50)
        #expect(xp.gameFullClearBonusXp == 200)
        #expect(xp.tripEndedBonusXp == 100)
        #expect(xp.tripParticipationBonusXp == 50)
        #expect(xp.tripCompetitiveFirstPlaceBonusXp == 25)
    }
}
