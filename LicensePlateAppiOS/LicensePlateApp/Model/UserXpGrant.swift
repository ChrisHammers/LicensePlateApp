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
    case competitiveFirstPlaceFinish = "competitive_first_place_finish"
    case achievementUnlock = "achievement_unlock"
    case legacyUnledgeredBalance = "legacy_unledgered_balance"
}
