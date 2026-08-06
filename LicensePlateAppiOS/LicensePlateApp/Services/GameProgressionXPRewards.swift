//
//  GameProgressionXPRewards.swift
//  LicensePlateApp
//
//  Deprecated shim — forwards to ProgressionRewardsConfigProvider.
//  Prefer ProgressionRewardsConfig.fixtureDefault in new tests.
//

import Foundation

enum GameProgressionXPRewards {
    static var baseDiscoveryXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseDiscoveryXp
    }
    static var firstFinderBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstFinderBonusXp
    }
    static var lifetimeUniqueRegionFindBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.lifetimeUniqueRegionFindBonusXp
    }
    static var firstFindOfDayBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstFindOfDayBonusXp
    }
    static var competitiveFirstPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveFirstPlaceFinishBonusXp
    }
    static var competitiveSecondPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveSecondPlaceFinishBonusXp
    }
    static var competitiveThirdPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveThirdPlaceFinishBonusXp
    }
    static var gameEndedBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.gameEndedBonusXp
    }
    static var gameFullClearBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.gameFullClearBonusXp
    }
    static var tripEndedBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.tripEndedBonusXp
    }
    static var tripParticipationBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.tripParticipationBonusXp
    }
    static var tripCompetitiveFirstPlaceBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.tripCompetitiveFirstPlaceBonusXp
    }
    /// Under Step 16.4 policy, local reconciliation never claws back XP.
    static var minimumLocalReconciliationDelta: Int {
        ProgressionRewardsConfigProvider.shared.current.policy.minimumLocalReconciliationDelta
    }
}
