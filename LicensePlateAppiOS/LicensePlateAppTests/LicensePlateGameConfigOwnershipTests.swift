//
//  LicensePlateGameConfigOwnershipTests.swift
//  LicensePlateAppTests
//
//  Step 6.9.2 — Enabled countries/region scope come from GameInstance.licensePlateConfig() and LicensePlateScopeCalculator.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct LicensePlateGameConfigOwnershipTests {

    @Test func enabledCountriesDerivedFromGameConfig() async throws {
        let config = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue], territoryOptions: LicensePlateTerritoryOptions())
        let targetIds = LicensePlateScopeCalculator.targetRegionIds(for: config)
        let countries = Set(PlateRegion.all.filter { targetIds.contains($0.id) }.map(\.country))
        #expect(countries == [.unitedStates])
    }

    @Test func gameInstanceWithPayloadDecodesConfigAndYieldsRegionIds() async throws {
        let config = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.canada.rawValue], territoryOptions: LicensePlateTerritoryOptions())
        let payloadData = try JSONEncoder().encode(config)
        let game = GameInstance(
            definitionId: GameType.licensePlate.rawValue,
            sessionId: UUID(),
            ruleSet: GameRuleSet(gameDefinitionId: GameType.licensePlate.rawValue),
            gameSpecificPayloadData: payloadData
        )
        let decoded = game.licensePlateConfig()
        #expect(decoded != nil)
        #expect(decoded?.selectedCountries == [.canada])
        let targetIds = LicensePlateScopeCalculator.targetRegionIds(for: decoded!)
        #expect(!targetIds.isEmpty)
    }

    @Test func completionGoalFromGameConfig() async throws {
        let config = LicensePlateGameConfig(selectedCountriesRawValues: [PlateRegion.Country.unitedStates.rawValue, PlateRegion.Country.canada.rawValue, PlateRegion.Country.mexico.rawValue], territoryOptions: LicensePlateTerritoryOptions())
        let goal = LicensePlateScopeCalculator.completionGoal(for: config)
        #expect(goal > 50)
    }
}
