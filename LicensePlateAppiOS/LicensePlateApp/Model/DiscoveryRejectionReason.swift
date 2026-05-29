//
//  DiscoveryRejectionReason.swift
//  LicensePlateApp
//
//  Canonical `rejectionReason` strings on `TripActivityEvent` (`discovery_rejected`) and server supersede paths.
//  Kept separate from `DiscoveryResolutionOutcome` (ledger reconciliation) to avoid name collisions.
//

import Foundation

enum DiscoveryRejectionReason: String, Codable, CaseIterable, Sendable {
    case serverRejectedLateCompetitive = "server_rejected_late_competitive"
    case serverRejectedSupersededByEarlierTimestamp = "server_rejected_superseded_by_earlier_timestamp"
    case rejectedInvalidParticipant = "rejected_invalid_participant"
    case rejectedDuplicate = "rejected_duplicate"
}
