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
    /// Raw values mirror `UserXpGrantReason` / server `XP_GRANT_REASON` so local rows and
    /// server grants group identically in the XP toast catalog.
    case competitiveFirstPlaceFinish = "competitive_first_place_finish"
    case competitiveSecondPlace = "competitive_second_place_finish"
    case competitiveThirdPlace = "competitive_third_place_finish"
    case tripEnded = "trip_ended"
    case tripParticipation = "trip_participation"
    case tripCompetitiveFirstPlace = "trip_competitive_first_place"
    case returnStreakDaily = "return_streak_daily"
    /// Legacy — unused for awards after XP grant rework.
    case tripCompletion = "trip_completion"
    case milestoneUnlock = "milestone_unlock"
}
