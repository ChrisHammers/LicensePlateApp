//
//  XpLedgerMetadataKey.swift
//  LicensePlateApp
//
//  Metadata keys on `XpLedgerEvent.metadata` for reconciliation and idempotency.
//

import Foundation

enum XpLedgerMetadataKey {
    /// Original `region_found` event id (stable after supersede deletes the activity row).
    static let originalDiscoveryEventId = "original_discovery_event_id"
    /// `DiscoveryResolution.resolutionId` applied by a compensating row (idempotent consume).
    static let resolutionId = "xp_resolution_id"
}
