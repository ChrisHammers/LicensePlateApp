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
    case tripCompletion = "trip_completion"
    case milestoneUnlock = "milestone_unlock"
    case returnStreakDaily = "return_streak_daily"
    case duplicateNoXp = "duplicate_no_xp"
    case personalRefindNoXp = "personal_refind_no_xp"
    case spamToggleNoXp = "spam_toggle_no_xp"
    case riskRejectedNoXp = "risk_rejected_no_xp"
}
