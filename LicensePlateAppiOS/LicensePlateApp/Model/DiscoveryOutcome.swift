//
//  DiscoveryOutcome.swift
//  LicensePlateApp
//
//  Step 03 — Centralized rules engine: outcome of evaluating a discovery submission (duplicate handling, attribution).
//

import Foundation

/// Result of evaluating a candidate discovery against existing discoveries for a target.
/// Raw values are snake_case for analytics.
enum DiscoveryOutcome: String, Codable, Sendable, CaseIterable {
    /// First find of this target; assign credit per mode.
    case newCredit = "new_credit"
    /// Same target found by another participant (collaborative); assign shared credit.
    case sharedDuplicate = "shared_duplicate"
    /// Same target found again by the same participant; no additional credit; append is allowed (advisory).
    case personalDuplicate = "personal_duplicate"
    /// Other participant already found this target (e.g. competitive); do not append.
    case rejectedDuplicate = "rejected_duplicate"
    /// Solo trip but discovery attributed to another participant; treat as invalid access / corrupted data; do not append.
    case rejectedInvalidParticipant = "rejected_invalid_participant"
    /// Server rejected a competitive `region_found` after sync (another finder won); audit + fairness UI.
    case serverRejectedLateCompetitive = "server_rejected_late_competitive"
}

/// Result of the rules engine evaluation for a single discovery submission.
/// Callers: use `shouldAppendEvent` to decide whether to persist the event; use `creditsToAssign` for analytics or future use (summary path uses creditsForDiscoveries instead).
struct DiscoveryEvaluationResult: Sendable {
    var outcome: DiscoveryOutcome
    var riskFlags: [RiskFlag]
    /// Credits that would be assigned for this submission; nil when rejected or personal_duplicate with no new credit.
    var creditsToAssign: [GameCredit]?

    /// When true, the event should be appended; when false (rejected_duplicate / rejected_invalid_participant), do not append.
    var shouldAppendEvent: Bool {
        switch outcome {
        case .rejectedDuplicate, .rejectedInvalidParticipant, .serverRejectedLateCompetitive:
            return false
        default:
            return true
        }
    }

    init(
        outcome: DiscoveryOutcome,
        riskFlags: [RiskFlag] = [],
        creditsToAssign: [GameCredit]? = nil
    ) {
        self.outcome = outcome
        self.riskFlags = riskFlags
        self.creditsToAssign = creditsToAssign
    }
}
