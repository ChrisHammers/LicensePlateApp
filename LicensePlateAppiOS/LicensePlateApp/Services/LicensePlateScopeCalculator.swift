//
//  LicensePlateScopeCalculator.swift
//  LicensePlateApp
//
//  Step 07.5 — Derive target region IDs and completion goal from LicensePlateGameConfig. Pure logic.
//  Step 6.9.x — explicit selected countries; RegionScope removed.
//

import Foundation

private let usDCId = "us-dc"
private let usTerritoryIds: Set<String> = ["us-pr", "us-gu", "us-vi", "us-as", "us-mp"]
private let canadianTerritoryIds: Set<String> = ["ca-nt", "ca-nu", "ca-yt"]

enum LicensePlateScopeCalculator {

    /// Returns target region IDs for the given config (subset of PlateRegion.all ids).
    static func targetRegionIds(for config: LicensePlateGameConfig) -> [String] {
        let all = PlateRegion.all
        let selected = Set(config.selectedCountries)
        guard !selected.isEmpty else { return [] }
        let filteredByCountry = all.filter { selected.contains($0.country) }
        return filterTerritories(filteredByCountry, options: config.territoryOptions).map(\.id)
    }

    /// Target region IDs as a set (for membership checks and UI filters).
    static func targetRegionIdSet(for config: LicensePlateGameConfig) -> Set<String> {
        Set(targetRegionIds(for: config))
    }

    /// Whether `regionId` is in the configured target set.
    static func isTargetRegion(_ regionId: String, config: LicensePlateGameConfig) -> Bool {
        targetRegionIdSet(for: config).contains(regionId)
    }

    /// Unique found region IDs that are also in scope for `config`.
    static func scopedUniqueFoundCount(foundRegionIds: some Sequence<String>, config: LicensePlateGameConfig) -> Int {
        let targets = targetRegionIdSet(for: config)
        guard !targets.isEmpty else { return 0 }
        return Set(foundRegionIds).intersection(targets).count
    }

    /// Unique discovery `targetId`s that are also in scope for `config`.
    static func scopedUniqueFoundCount(discoveries: [GameDiscovery], config: LicensePlateGameConfig) -> Int {
        scopedUniqueFoundCount(foundRegionIds: discoveries.map(\.targetId), config: config)
    }

    /// Completion goal (number of target regions) for the given config.
    static func completionGoal(for config: LicensePlateGameConfig) -> Int {
        targetRegionIds(for: config).count
    }

    private static func filterTerritories(_ regions: [PlateRegion], options: LicensePlateTerritoryOptions) -> [PlateRegion] {
        regions.filter { region in
            if region.country == .unitedStates {
                if region.id == usDCId { return options.includeDC }
                if usTerritoryIds.contains(region.id) { return options.includeUSTerritories }
                return true
            }
            if region.country == .canada && canadianTerritoryIds.contains(region.id) {
                return options.includeCanadianTerritories
            }
            return true
        }
    }
}
