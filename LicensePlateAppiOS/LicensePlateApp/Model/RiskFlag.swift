//
//  RiskFlag.swift
//  LicensePlateApp
//
//  Step 11 expected structure — Typed risk flag (id, type, severity, source, metadata, presentation key).
//

import Foundation

/// Typed risk flag for discovery; attachable to GameDiscovery. Use presentationKey for UI copy lookup.
struct RiskFlag: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var discoveryId: String?
    var type: RiskFlagType
    var severity: RiskSeverity
    var source: RiskSource
    var createdAt: Date

    /// Stable key for UI copy lookup, not raw display text.
    var presentationKey: String

    var metadata: RiskFlagMetadata

    init(
        id: UUID = UUID(),
        discoveryId: String? = nil,
        type: RiskFlagType,
        severity: RiskSeverity,
        source: RiskSource = .localHeuristic,
        createdAt: Date = Date(),
        presentationKey: String,
        metadata: RiskFlagMetadata = RiskFlagMetadata()
    ) {
        self.id = id
        self.discoveryId = discoveryId
        self.type = type
        self.severity = severity
        self.source = source
        self.createdAt = createdAt
        self.presentationKey = presentationKey
        self.metadata = metadata
    }
}
