//
//  GameProgressionXPRewards.swift
//  LicensePlateApp
//
//  Centralized local XP tuning values for Step 16.4.
//

import Foundation

enum GameProgressionXPRewards {
    /// Base XP for the first eligible scoped discovery grant (any mode).
    static let baseDiscoveryXp: Int = 10
    /// Extra  bonus for first finder (any multiplayer mode)
    static let firstFinderBonusXp: Int = 5
    /// Extra  bonus for first time finding that plate (any mode)
    static let firstPlateFindBonusXp: Int = 15
    
    static let baseMultiplayerGameBonusXp: Int = 15
    /// Extra competitive bonus granted at game end to rank-1 participants.
    static let competitiveFirstPlaceFinishBonusXp: Int = 15
    /// Extra competitive bonus granted at game end to rank-2 participants.
    static let competitiveSecondPlaceFinishBonusXp: Int = 10
    /// Extra competitive bonus granted at game end to rank-3 participants.
    static let competitiveThirdPlaceFinishBonusXp: Int = 5
    
    /// Extra bonus  XP  for contributing to game (any mode)
    static let gameContributorBonusXp: Int = 5
    /// Extra bonus for contributing to trip (any modes)
    static let tripContributorBonusXp: Int = 10
    
    
    /// Milestones XP
    
    /// Bonus XP for first Trip Completed (make sure they Rank up)
    static let firstTripCompletionBonusXp: Int = 15
    /// Bonus XP for first Multiplayer Trip Completed (make sure they Rank up)
    static let firstMuliplayerTripCompletionBonusXp: Int = 15
    /// Bonus XP for first Game Completed (make sure they Rank up)
    static let firstGameCompletionBonusXp: Int = 15
    /// Bonus XP for first Multiplayer Game Completed (make sure they Rank up)
    static let firstMulitplayerGameCompletionBonusXp: Int = 15
    
    /// Base XP for a Milestones
    static let baseMilestoneBonusXp: Int = 25
    

    /// Under Step 16.4 policy, local reconciliation never claws back XP.
    static let minimumLocalReconciliationDelta: Int = 0
}
