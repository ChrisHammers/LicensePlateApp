//
//  RiskFlagType.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Typed risk flag kinds for discovery spam / suspicious usage.
//

import Foundation

/// Type of risk detected; raw value for analytics (snake_case).
enum RiskFlagType: String, Codable, Sendable, CaseIterable {
    case rapidDiscovery = "rapid_discovery"
    case rapidUndoRedo = "rapid_undo_redo"
    case duplicateDiscovery = "duplicate_discovery"
    case impossibleTimestamp = "impossible_timestamp"
    case impossibleLocation = "impossible_location"
    case suspiciousToggleLoop = "suspicious_toggle_loop"
    case burstInputPattern = "burst_input_pattern"
}
