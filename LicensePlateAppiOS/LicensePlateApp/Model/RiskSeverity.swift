//
//  RiskSeverity.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Severity level for risk flags; used for presentation mapping.
//

import Foundation

enum RiskSeverity: String, Codable, Sendable, Comparable {
    case notice
    case warning
    case review

    static func < (lhs: RiskSeverity, rhs: RiskSeverity) -> Bool {
        let order: [RiskSeverity: Int] = [
            .notice: 0,
            .warning: 1,
            .review: 2
        ]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}
