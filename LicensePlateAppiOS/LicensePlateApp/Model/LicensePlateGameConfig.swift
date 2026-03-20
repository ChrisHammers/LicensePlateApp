//
//  LicensePlateGameConfig.swift
//  LicensePlateApp
//
//  Step 07.5 — License-plate game-specific config.
//  Step 6.9.x — explicit selected countries + territory options. Completion goal is derived.
//

import Foundation

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
    /// Persisted as raw values to keep payload Codable-only and independent of enum evolution.
    var selectedCountriesRawValues: [String]
    var territoryOptions: LicensePlateTerritoryOptions

    init(
        selectedCountriesRawValues: [String] = [
            PlateRegion.Country.unitedStates.rawValue,
            PlateRegion.Country.canada.rawValue,
            PlateRegion.Country.mexico.rawValue
        ],
        territoryOptions: LicensePlateTerritoryOptions = LicensePlateTerritoryOptions()
    ) {
        self.selectedCountriesRawValues = selectedCountriesRawValues
        self.territoryOptions = territoryOptions
    }

    /// Typed selected countries for UI and calculation code.
    var selectedCountries: [PlateRegion.Country] {
        get { selectedCountriesRawValues.compactMap(PlateRegion.Country.init(rawValue:)) }
        set { selectedCountriesRawValues = newValue.map(\.rawValue) }
    }
}
