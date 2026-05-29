//
//  XpGrantKind.swift
//  LicensePlateApp
//
//  XP ledger — kind of grant row (append-only ledger).
//

import Foundation

enum XpGrantKind: String, Codable, CaseIterable, Sendable {
    case provisionalDiscoveryXp = "provisional_discovery_xp"
    case reconciliationAdjustment = "reconciliation_adjustment"
    case finalDiscoveryAward = "final_discovery_award"
    case tripCompletion = "trip_completion"
    case milestoneUnlock = "milestone_unlock"
}
