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
}

/// Trip-scoring layer outcome (separate type from discovery XP semantics).
enum TripScoringOutcome: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case acceptedFirst = "accepted_first"
    case acceptedLate = "accepted_late"
    case acceptedShared = "accepted_shared"
}

/// Personal travel-history layer outcome.
enum PersonalHistoryOutcome: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case acceptedFirst = "accepted_first"
    case acceptedLate = "accepted_late"
    case acceptedShared = "accepted_shared"
}
