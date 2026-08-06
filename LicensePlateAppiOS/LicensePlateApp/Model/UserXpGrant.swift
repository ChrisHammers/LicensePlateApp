//
//  UserXpGrant.swift
//  LicensePlateApp
//
//  Server-authoritative append-only XP grant row (`user_progression/{uid}/xp_grants/{grantId}`).
//

import Foundation

struct UserXpGrant: Equatable, Sendable, Identifiable {
    var grantId: String
    var amount: Int
    var reason: String
    var sourceType: String
    var sourceId: String
    var idempotencyKey: String
    var sessionId: String?
    var achievementId: String?
    var xpRewardAtGrant: Int?
    var grantedAt: Date?

    var id: String { grantId }
}

enum UserXpGrantReason: String, Sendable {
    case regionFoundBaseDiscovery = "region_found_base_discovery"
    case competitiveFirstFinder = "competitive_first_finder"
    case lifetimeUniqueRegion = "lifetime_unique_region"
    case firstFindOfDay = "first_find_of_day"
    case competitiveFirstPlaceFinish = "competitive_first_place_finish"
    case competitiveSecondPlaceFinish = "competitive_second_place_finish"
    case competitiveThirdPlaceFinish = "competitive_third_place_finish"
    case gameEnded = "game_ended"
    case gameFullClear = "game_full_clear"
    case tripEnded = "trip_ended"
    case tripParticipation = "trip_participation"
    case tripCompetitiveFirstPlace = "trip_competitive_first_place"
    case achievementUnlock = "achievement_unlock"
    case returnStreakDaily = "return_streak_daily"
    case legacyUnledgeredBalance = "legacy_unledgered_balance"
}
