//
//  LicensePlateGameConfig.swift
//  LicensePlateApp
//
//  Step 07.5 — License-plate game-specific config: region scope and territory options. Completion goal is derived.
//

import Foundation

/// Region scope for license plate game. Combinations expressed by including multiple countries.
enum RegionScope: String, Codable, CaseIterable, Sendable {
    case usOnly = "us"
    case canadaOnly = "canada"
    case mexicoOnly = "mexico"
    case northAmerica = "north_america"
}

/// Territory inclusion options for license plate game. Completion goal is derived from scope + these options.
struct LicensePlateTerritoryOptions: Codable, Sendable {
    var includeUSTerritories: Bool
    var includeCanadianTerritories: Bool
    var includeDC: Bool

    init(
        includeUSTerritories: Bool = true,
        includeCanadianTerritories: Bool = true,
        includeDC: Bool = true
    ) {
        self.includeUSTerritories = includeUSTerritories
        self.includeCanadianTerritories = includeCanadianTerritories
        self.includeDC = includeDC
    }
}

/// Game-specific configuration for the license plate game type. Completion goal is not stored; use LicensePlateScopeCalculator.
struct LicensePlateGameConfig: Codable, Sendable {
    var regionScope: RegionScope
    var territoryOptions: LicensePlateTerritoryOptions

    init(
        regionScope: RegionScope = .northAmerica,
        territoryOptions: LicensePlateTerritoryOptions = LicensePlateTerritoryOptions()
    ) {
        self.regionScope = regionScope
        self.territoryOptions = territoryOptions
    }
}
