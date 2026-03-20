//
//  LicensePlateScopeCalculatorTests.swift
//  LicensePlateAppTests
//
//  Step 07.5 — Region scope and completion goal from LicensePlateGameConfig.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LicensePlateScopeCalculatorTests {

    @Test func usOnlyStatesOnlyReturns50() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: false)
        )
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: config)
        #expect(ids.count == 50)
        #expect(ids.contains("us-dc") == false)
        #expect(ids.contains("us-pr") == false)
    }

    @Test func usOnlyWithDCReturns51() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: true)
        )
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == 51)
    }

    @Test func usOnlyWithDCAndTerritoriesReturns56() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: true, includeCanadianTerritories: true, includeDC: true)
        )
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == 56)
    }

    @Test func canadaOnlyProvincesOnlyReturns10() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.canada.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: false, includeDC: false)
        )
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == 10)
    }

    @Test func canadaOnlyWithTerritoriesReturns13() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.canada.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: false)
        )
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == 13)
    }

    @Test func mexicoOnlyReturns32() async throws {
        let config = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.mexico.rawValue])
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == 32)
    }

    @Test func northAmericaFullReturnsCorrectTotal() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: true, includeCanadianTerritories: true, includeDC: true)
        )
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: config)
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(ids.count == goal)
        #expect(goal == 56 + 13 + 32)
    }

    @Test func completionGoalMatchesTargetRegionIdsCount() async throws {
        let config = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue])
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: config)
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal == ids.count)
    }

    @Test func usAndCanadaOnlyExcludesMexico() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: false, includeDC: false)
        )
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: config)
        #expect(ids.contains(where: { $0.hasPrefix("mx-") }) == false)
        #expect(ids.count == 60) // 50 US states + 10 CA provinces
    }

    @Test func usAndMexicoOnlyExcludesCanada() async throws {
        let config = LicensePlateGameConfig(
            selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.mexico.rawValue],
            territoryOptions: LicensePlateTerritoryOptions(includeUSTerritories: false, includeCanadianTerritories: true, includeDC: false)
        )
        let ids = LicensePlateScopeCalculator.targetRegionIds(for: config)
        #expect(ids.contains(where: { $0.hasPrefix("ca-") }) == false)
        #expect(ids.count == 82) // 50 US states + 32 Mexico states
    }
}
