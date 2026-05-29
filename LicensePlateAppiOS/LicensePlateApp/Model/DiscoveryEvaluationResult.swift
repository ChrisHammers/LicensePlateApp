//
//  DiscoveryEvaluationResult.swift
//  LicensePlateApp
//
//  Result of `DiscoveryRulesEngine.evaluateDiscoverySubmission` (local rules before append).
//

import Foundation

/// Local evaluation label for a discovery submission (distinct from `DiscoveryRejectionReason` / server payload strings).
enum DiscoveryEvaluationOutcome: String, Codable, CaseIterable, Sendable {
    case newCredit = "new_credit"
    case personalDuplicate = "personal_duplicate"
    case rejectedInvalidParticipant = "rejected_invalid_participant"
    case rejectedDuplicate = "rejected_duplicate"
    case sharedDuplicate = "shared_duplicate"
}

struct DiscoveryEvaluationResult: Sendable, Equatable {
    var outcome: DiscoveryEvaluationOutcome
    var riskFlags: [RiskFlag]
    var creditsToAssign: [GameCredit]?

    /// Whether the caller should append a gameplay event (`region_found` path). Rejected outcomes are handled separately in the ViewModel.
    var shouldAppendEvent: Bool {
        switch outcome {
        case .newCredit, .personalDuplicate, .sharedDuplicate:
            return true
        case .rejectedDuplicate, .rejectedInvalidParticipant:
            return false
        }
    }
}
