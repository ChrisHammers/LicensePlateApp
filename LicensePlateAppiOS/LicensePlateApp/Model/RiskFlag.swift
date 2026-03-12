//
//  RiskFlag.swift
//  LicensePlateApp
//
//  Step 11 — Advisory risk flags for discovery spam / suspicious usage. Used by RiskAssessmentService and analytics.
//

import Foundation

/// Advisory risk flag kinds. Raw value used for GameDiscovery.riskFlag and analytics (snake_case).
enum RiskFlag: String, Sendable, CaseIterable {
    case impossibleBurst = "impossible_burst"
    case rapidFindUnfindLoop = "rapid_find_unfind_loop"
    case suspiciousRepeatedToggles = "suspicious_repeated_toggles"
    case duplicateDiscoveryAnomaly = "duplicate_discovery_anomaly"
    case conflictingLocalTimestamp = "conflicting_local_timestamp"
}
