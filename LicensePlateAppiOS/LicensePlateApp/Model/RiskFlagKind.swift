//
//  RiskFlagKind.swift
//  LicensePlateApp
//
//  Step 11 — Legacy advisory risk flag kinds (String raw). Prefer RiskFlag struct + RiskFlagType for new code.
//

import Foundation

/// Advisory risk flag kinds. Raw value for analytics (snake_case). Use typed RiskFlag struct where possible.
enum RiskFlagKind: String, Sendable, CaseIterable {
    case impossibleBurst = "impossible_burst"
    case rapidFindUnfindLoop = "rapid_find_unfind_loop"
    case suspiciousRepeatedToggles = "suspicious_repeated_toggles"
    case duplicateDiscoveryAnomaly = "duplicate_discovery_anomaly"
    case conflictingLocalTimestamp = "conflicting_local_timestamp"
}
