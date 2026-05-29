//
//  DiscoveryOutcome.swift
//  LicensePlateApp
//
//  `DiscoveryResolutionOutcome` — post-reconciliation discovery result (XP ledger / `DiscoveryResolution`).
//  `TripScoringOutcome` / `PersonalHistoryOutcome` — separate axes for trip scoring vs travel history.
//  Wire `discovery_rejected` payload reasons live in `DiscoveryRejectionReason.swift`.
//

import Foundation

/// Outcome of competitive/shared discovery resolution for the finder (ledger / resolution record).
enum DiscoveryResolutionOutcome: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case acceptedFirst = "accepted_first"
    case acceptedLate = "accepted_late"
    case acceptedShared = "accepted_shared"
    case rejectedDuplicate = "rejected_duplicate"
    case rejectedPersonalDuplicate = "rejected_personal_duplicate"
    case rejectedRisk = "rejected_risk"
    case rejectedInvalidState = "rejected_invalid_state"
}

/// Trip-scoring layer outcome (separate type from discovery XP semantics).
enum TripScoringOutcome: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case acceptedFirst = "accepted_first"
    case acceptedLate = "accepted_late"
    case acceptedShared = "accepted_shared"
    case rejectedDuplicate = "rejected_duplicate"
    case rejectedPersonalDuplicate = "rejected_personal_duplicate"
    case rejectedRisk = "rejected_risk"
    case rejectedInvalidState = "rejected_invalid_state"
}

/// Personal travel-history layer outcome (refinds, duplicates, etc.).
enum PersonalHistoryOutcome: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case acceptedFirst = "accepted_first"
    case acceptedLate = "accepted_late"
    case acceptedShared = "accepted_shared"
    case rejectedDuplicate = "rejected_duplicate"
    case rejectedPersonalDuplicate = "rejected_personal_duplicate"
    case rejectedRisk = "rejected_risk"
    case rejectedInvalidState = "rejected_invalid_state"
}
