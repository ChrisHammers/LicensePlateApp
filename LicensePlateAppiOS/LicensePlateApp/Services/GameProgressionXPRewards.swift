//
//  GameProgressionXPRewards.swift
//  LicensePlateApp
//
//  Deprecated shim — forwards to ProgressionRewardsConfigProvider.
//  Prefer ProgressionRewardsConfig.fixtureDefault in new tests.
//

import Foundation

enum GameProgressionXPRewards {
    /// Base XP for the first eligible scoped discovery grant (any mode).
    static var baseDiscoveryXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseDiscoveryXp
    }
    /// Extra bonus for first finder (any multiplayer mode)
    static var firstFinderBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstFinderBonusXp
    }
    /// Extra bonus for first time finding that plate (any mode)
    static var firstPlateFindBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstPlateFindBonusXp
    }
    /// Base XP for playing a game with friends (any multiplayer mode, collab)
    static var baseMultiplayerGameBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseMultiplayerGameBonusXp
    }
    /// Extra competitive bonus granted at game end to rank-1 participants.
    static var competitiveFirstPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveFirstPlaceFinishBonusXp
    }
    /// Extra competitive bonus granted at game end to rank-2 participants.
    static var competitiveSecondPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveSecondPlaceFinishBonusXp
    }
    /// Extra competitive bonus granted at game end to rank-3 participants.
    static var competitiveThirdPlaceFinishBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.competitiveThirdPlaceFinishBonusXp
    }
    /// Extra bonus XP for contributing to game (any mode)
    static var gameContributorBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.gameContributorBonusXp
    }
    /// Extra bonus for contributing to trip (any modes)
    static var tripContributorBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.tripContributorBonusXp
    }
    /// Bonus XP for first Trip Completed (make sure they Rank up)
    static var firstTripCompletionBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstTripCompletionBonusXp
    }
    /// Bonus XP for first Multiplayer Trip Completed (make sure they Rank up)
    static var firstMuliplayerTripCompletionBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstMultiplayerTripCompletionBonusXp
    }
    /// Bonus XP for first Game Completed (make sure they Rank up)
    static var firstGameCompletionBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstGameCompletionBonusXp
    }
    /// Bonus XP for first Multiplayer Game Completed (make sure they Rank up)
    static var firstMulitplayerGameCompletionBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.firstMultiplayerGameCompletionBonusXp
    }
    /// Base XP for a Milestones
    static var baseMilestoneBonusXp: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseMilestoneBonusXp
    }
    /// Under Step 16.4 policy, local reconciliation never claws back XP.
    static var minimumLocalReconciliationDelta: Int {
        ProgressionRewardsConfigProvider.shared.current.policy.minimumLocalReconciliationDelta
    }
}
