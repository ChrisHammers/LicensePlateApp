//
//  XpReasonCode.swift
//  LicensePlateApp
//

import Foundation

enum XpReasonCode: String, Codable, CaseIterable, Sendable {
    case discoveryClaimPendingResolution = "discovery_claim_pending_resolution"
    case competitiveFirstFinder = "competitive_first_finder"
    case competitiveLateFinder = "competitive_late_finder"
    case collaborativeSharedFinder = "collaborative_shared_finder"
    case soloNewDiscovery = "solo_new_discovery"
    case lifetimeUniqueRegion = "lifetime_unique_region"
    case firstFindOfDay = "first_find_of_day"
    case gameEnded = "game_ended"
    case gameFullClear = "game_full_clear"
    case competitiveSecondPlace = "competitive_second_place_finish"
    case competitiveThirdPlace = "competitive_third_place_finish"
    case tripEnded = "trip_ended"
    case tripParticipation = "trip_participation"
    case tripCompetitiveFirstPlace = "trip_competitive_first_place"
    case returnStreakDaily = "return_streak_daily"
    case duplicateNoXp = "duplicate_no_xp"
    case personalRefindNoXp = "personal_refind_no_xp"
    case spamToggleNoXp = "spam_toggle_no_xp"
    case riskRejectedNoXp = "risk_rejected_no_xp"
    /// Legacy — unused for awards after XP grant rework.
    case tripCompletion = "trip_completion"
    case milestoneUnlock = "milestone_unlock"
}
