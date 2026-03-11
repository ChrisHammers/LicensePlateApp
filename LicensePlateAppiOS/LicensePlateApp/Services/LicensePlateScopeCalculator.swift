//
//  LicensePlateScopeCalculator.swift
//  LicensePlateApp
//
//  Step 07.5 — Derive target region IDs and completion goal from LicensePlateGameConfig. Pure logic.
//

import Foundation

private let usDCId = "us-dc"
private let usTerritoryIds: Set<String> = ["us-pr", "us-gu", "us-vi", "us-as", "us-mp"]
private let canadianTerritoryIds: Set<String> = ["ca-nt", "ca-nu", "ca-yt"]

enum LicensePlateScopeCalculator {

    /// Returns target region IDs for the given config (subset of PlateRegion.all ids).
    static func targetRegionIds(for config: LicensePlateGameConfig) -> [String] {
        let all = PlateRegion.all
        switch config.regionScope {
        case .usOnly:
            return filterUS(all, includeDC: config.territoryOptions.includeDC, includeUSTerritories: config.territoryOptions.includeUSTerritories).map(\.id)
        case .canadaOnly:
            return filterCanada(all, includeTerritories: config.territoryOptions.includeCanadianTerritories).map(\.id)
        case .mexicoOnly:
            return all.filter { $0.country == .mexico }.map(\.id)
        case .northAmerica:
            let usIds = filterUS(all, includeDC: config.territoryOptions.includeDC, includeUSTerritories: config.territoryOptions.includeUSTerritories).map(\.id)
            let caIds = filterCanada(all, includeTerritories: config.territoryOptions.includeCanadianTerritories).map(\.id)
            let mxIds = all.filter { $0.country == .mexico }.map(\.id)
            return usIds + caIds + mxIds
        }
    }

    /// Completion goal (number of target regions) for the given config.
    static func completionGoal(for config: LicensePlateGameConfig) -> Int {
        targetRegionIds(for: config).count
    }

    private static func filterUS(_ regions: [PlateRegion], includeDC: Bool, includeUSTerritories: Bool) -> [PlateRegion] {
        regions.filter { region in
            guard region.country == .unitedStates else { return false }
            if region.id == usDCId { return includeDC }
            if usTerritoryIds.contains(region.id) { return includeUSTerritories }
            return true // 50 states
        }
    }

    private static func filterCanada(_ regions: [PlateRegion], includeTerritories: Bool) -> [PlateRegion] {
        regions.filter { region in
            guard region.country == .canada else { return false }
            if canadianTerritoryIds.contains(region.id) { return includeTerritories }
            return true
        }
    }
}
