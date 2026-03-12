//
//  UITestTripBuilder.swift
//  LicensePlateAppUITests
//
//  Step 13 — Deterministic trip/game data for UI test assertions. Aligns with PreviewFixtures IDs.
//

import Foundation

/// Builds trip/game identifiers and labels that match PreviewFixtures and MockFactories
/// so UI tests can assert on predictable accessibility labels or text.
enum UITestTripBuilder {
    static let sessionIdSolo = "E621E1F8-C36C-4A1B-9F2D-111111111111"
    static let sessionIdMulti = "E621E1F8-C36C-4A1B-9F2D-222222222222"
    static let tripNameSolo = "Solo Road Trip"
    static let tripNameMulti = "Multi-Game Trip"
}

enum UITestGameBuilder {
    static let gameInstanceId1 = "A1111111-1111-1111-1111-111111111111"
    static let gameInstanceId2 = "A2222222-2222-2222-2222-222222222222"
    static let licensePlateGameDefinitionId = "license_plate"
}
