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
    /// Raw values mirror `UserXpGrantReason` / server `XP_GRANT_REASON`. For `trip_ended` (like
    /// `game_ended` and `game_full_clear` above) that pairs the local row with the server grant in
    /// the XP toast catalog. The five `serverDecidedCompletion` reasons never label a local row
    /// (§3.1.1 item 25); their raw values are how `XpFeedProjectionBuilder` parses the server grant.
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

    /// Completion awards the server alone decides, from the events it holds at game / trip end
    /// (§3.1.1 item 25, OD-17): competitive placement, trip competitive first and trip
    /// participation. No local ledger row ever carries one; the server's `xp_grants` row is the
    /// award's only source. `XpServerScopeKey.mirrored(for:)` keeps its own exhaustive arm for them.
    static let serverDecidedCompletion: Set<XpReasonCode> = [
        .competitiveFirstPlaceFinish, .competitiveSecondPlace, .competitiveThirdPlace,
        .tripParticipation, .tripCompetitiveFirstPlace,
    ]
}
