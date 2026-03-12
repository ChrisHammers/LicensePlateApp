//
//  RiskFlagMetadata.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Structured metadata for risk flags (analytics and review).
//

import Foundation

struct RiskFlagMetadata: Codable, Sendable, Equatable {
    var burstCount: Int?
    var toggleLoopCount: Int?
    var duplicateIntervalSeconds: TimeInterval?
    var anomalyDistanceMeters: Double?
    var timeDeltaSeconds: TimeInterval?

    init(
        burstCount: Int? = nil,
        toggleLoopCount: Int? = nil,
        duplicateIntervalSeconds: TimeInterval? = nil,
        anomalyDistanceMeters: Double? = nil,
        timeDeltaSeconds: TimeInterval? = nil
    ) {
        self.burstCount = burstCount
        self.toggleLoopCount = toggleLoopCount
        self.duplicateIntervalSeconds = duplicateIntervalSeconds
        self.anomalyDistanceMeters = anomalyDistanceMeters
        self.timeDeltaSeconds = timeDeltaSeconds
    }
}
